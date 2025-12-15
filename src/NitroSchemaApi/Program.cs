using System.Net.WebSockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Npgsql;

var builder = WebApplication.CreateBuilder(args);

var postgres = builder.Configuration.GetConnectionString("postgres");
if (string.IsNullOrWhiteSpace(postgres))
{
    throw new InvalidOperationException("Missing ConnectionStrings:postgres");
}

var adminToken = builder.Configuration["Nitro:AdminToken"]
                 ?? Environment.GetEnvironmentVariable("NITRO_ADMIN_TOKEN")
                 ?? string.Empty;

builder.Services.AddSingleton(new NpgsqlDataSourceBuilder(postgres).Build());
builder.Services.AddSingleton<FgpStore>();
builder.Services.AddSingleton<WebSocketHub>();
builder.Services.AddHostedService<DbInitService>();

var app = builder.Build();

app.UseWebSockets();

app.MapGet("/", () => Results.Ok(new { name = "nitro-schema-api", status = "running" }));
app.MapGet("/health", () => Results.Ok("healthy"));

app.Map("/ws", async (HttpContext context, WebSocketHub hub, FgpStore store, ILoggerFactory loggerFactory) =>
{
    if (!context.WebSockets.IsWebSocketRequest)
    {
        context.Response.StatusCode = StatusCodes.Status400BadRequest;
        return;
    }

    var logger = loggerFactory.CreateLogger("nitro-schema-api.ws");
    using var socket = await context.WebSockets.AcceptWebSocketAsync();

    var connectionId = hub.Add(socket);

    try
    {
        // Always send latest on connect to satisfy "new gateway bootstrap".
        try
        {
            var latest = await store.GetLatestAsync(context.RequestAborted);
            if (latest is not null)
            {
                await hub.SendAsync(socket, NitroMessage.Latest(latest.Etag, latest.Version, latest.Fgp), context.RequestAborted);
            }
        }
        catch (Exception ex) when (ex is NpgsqlException)
        {
            logger.LogWarning(ex, "DB unavailable during bootstrap");
            await hub.SendAsync(socket, NitroMessage.Error("db_unavailable"), context.RequestAborted);
        }

        while (!context.RequestAborted.IsCancellationRequested && socket.State == WebSocketState.Open)
        {
            var json = await ReceiveTextMessageAsync(socket, maxMessageBytes: 100 * 1024 * 1024, context.RequestAborted);
            if (json is null)
            {
                break;
            }

            NitroInbound? inbound;
            try
            {
                inbound = JsonSerializer.Deserialize<NitroInbound>(json);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Failed to parse WS message");
                await hub.SendAsync(socket, NitroMessage.Error("invalid_json"), context.RequestAborted);
                continue;
            }

            if (inbound?.Type is null)
            {
                await hub.SendAsync(socket, NitroMessage.Error("missing_type"), context.RequestAborted);
                continue;
            }

            switch (inbound.Type)
            {
                case "HELLO":
                case "GET_LATEST":
                {
                    try
                    {
                        var current = await store.GetLatestAsync(context.RequestAborted);
                        if (current is null)
                        {
                            await hub.SendAsync(socket, NitroMessage.Error("no_fgp_published"), context.RequestAborted);
                            break;
                        }

                        await hub.SendAsync(socket, NitroMessage.Latest(current.Etag, current.Version, current.Fgp), context.RequestAborted);
                    }
                    catch (Exception ex) when (ex is NpgsqlException)
                    {
                        logger.LogWarning(ex, "DB unavailable during GET_LATEST");
                        await hub.SendAsync(socket, NitroMessage.Error("db_unavailable"), context.RequestAborted);
                    }
                    break;
                }

                case "PUBLISH":
                {
                    if (string.IsNullOrWhiteSpace(adminToken))
                    {
                        await hub.SendAsync(socket, NitroMessage.Error("publishing_disabled"), context.RequestAborted);
                        break;
                    }

                    if (!TokensMatch(adminToken, inbound.Token))
                    {
                        await hub.SendAsync(socket, NitroMessage.Error("unauthorized"), context.RequestAborted);
                        break;
                    }

                    if (string.IsNullOrWhiteSpace(inbound.FgpBase64))
                    {
                        await hub.SendAsync(socket, NitroMessage.Error("missing_fgp"), context.RequestAborted);
                        break;
                    }

                    string fgp;
                    try
                    {
                        fgp = Encoding.UTF8.GetString(Convert.FromBase64String(inbound.FgpBase64));
                    }
                    catch
                    {
                        await hub.SendAsync(socket, NitroMessage.Error("invalid_base64"), context.RequestAborted);
                        break;
                    }

                    var etag = ComputeSha256Hex(fgp);
                    try
                    {
                        var updated = await store.PublishAsync(etag, fgp, context.RequestAborted);
                        await hub.BroadcastAsync(NitroMessage.FgpUpdated(updated.Etag, updated.Version, updated.Fgp), context.RequestAborted);
                    }
                    catch (Exception ex) when (ex is NpgsqlException)
                    {
                        logger.LogWarning(ex, "DB unavailable during PUBLISH");
                        await hub.SendAsync(socket, NitroMessage.Error("db_unavailable"), context.RequestAborted);
                    }
                    break;
                }

                default:
                    await hub.SendAsync(socket, NitroMessage.Error("unknown_type"), context.RequestAborted);
                    break;
            }
        }
    }
    finally
    {
        hub.Remove(connectionId);
        try { await socket.CloseAsync(WebSocketCloseStatus.NormalClosure, "closing", CancellationToken.None); } catch { }
    }
});

app.Run();

static async Task<string?> ReceiveTextMessageAsync(WebSocket socket, int maxMessageBytes, CancellationToken cancellationToken)
{
    var buffer = new byte[16 * 1024];
    using var ms = new MemoryStream();

    while (true)
    {
        var result = await socket.ReceiveAsync(buffer, cancellationToken);
        if (result.MessageType == WebSocketMessageType.Close)
        {
            return null;
        }

        if (result.MessageType != WebSocketMessageType.Text)
        {
            // Ignore non-text frames.
            if (result.EndOfMessage)
            {
                return null;
            }

            continue;
        }

        ms.Write(buffer, 0, result.Count);
        if (ms.Length > maxMessageBytes)
        {
            throw new InvalidOperationException($"WS message exceeded limit ({maxMessageBytes} bytes)");
        }

        if (result.EndOfMessage)
        {
            return Encoding.UTF8.GetString(ms.ToArray());
        }
    }
}

static string ComputeSha256Hex(string input)
{
    var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(input));
    return Convert.ToHexString(bytes).ToLowerInvariant();
}

static bool TokensMatch(string expected, string? provided)
{
    if (string.IsNullOrWhiteSpace(expected))
    {
        return false;
    }

    var a = Encoding.UTF8.GetBytes(expected);
    var b = Encoding.UTF8.GetBytes(provided ?? string.Empty);

    if (a.Length != b.Length)
    {
        return false;
    }

    return CryptographicOperations.FixedTimeEquals(a, b);
}

sealed record NitroInbound
{
    public string? Type { get; init; }
    public string? Token { get; init; }
    public string? FgpBase64 { get; init; }
}

sealed record FgpRow(string Etag, long Version, string Fgp);

sealed class DbInitService(NpgsqlDataSource dataSource, ILogger<DbInitService> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var delay = TimeSpan.FromSeconds(1);
        var maxDelay = TimeSpan.FromSeconds(10);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await using var conn = await dataSource.OpenConnectionAsync(stoppingToken);
                await using var cmd = conn.CreateCommand();
                cmd.CommandText = @"
CREATE TABLE IF NOT EXISTS nitro_fgp_current (
  id          INT PRIMARY KEY,
  version     BIGINT NOT NULL,
  etag        TEXT NOT NULL,
  fgp         TEXT NOT NULL,
  updated_at  TIMESTAMPTZ NOT NULL
);
";
                await cmd.ExecuteNonQueryAsync(stoppingToken);
                logger.LogInformation("Ensured nitro_fgp_current table exists");
                return;
            }
            catch (OperationCanceledException)
            {
                return;
            }
            catch (Exception ex) when (ex is NpgsqlException)
            {
                logger.LogWarning(ex, "Postgres not ready; retrying in {DelaySeconds:n0}s", delay.TotalSeconds);
                await Task.Delay(delay, stoppingToken);
                delay = TimeSpan.FromSeconds(Math.Min(maxDelay.TotalSeconds, delay.TotalSeconds * 2));
            }
        }
    }
}

sealed class FgpStore(NpgsqlDataSource dataSource)
{
    public async Task<FgpRow?> GetLatestAsync(CancellationToken cancellationToken)
    {
        await using var conn = await dataSource.OpenConnectionAsync(cancellationToken);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT etag, version, fgp FROM nitro_fgp_current WHERE id = 1";

        await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new FgpRow(
            reader.GetString(0),
            reader.GetInt64(1),
            reader.GetString(2));
    }

    public async Task<FgpRow> PublishAsync(string etag, string fgp, CancellationToken cancellationToken)
    {
        await using var conn = await dataSource.OpenConnectionAsync(cancellationToken);
        await using var tx = await conn.BeginTransactionAsync(cancellationToken);

        long nextVersion;
        await using (var get = conn.CreateCommand())
        {
            get.Transaction = tx;
            get.CommandText = "SELECT version FROM nitro_fgp_current WHERE id = 1";
            var existing = await get.ExecuteScalarAsync(cancellationToken);
            nextVersion = existing is null ? 1 : ((long)existing) + 1;
        }

        await using (var upsert = conn.CreateCommand())
        {
            upsert.Transaction = tx;
            upsert.CommandText = @"
INSERT INTO nitro_fgp_current (id, version, etag, fgp, updated_at)
VALUES (1, @version, @etag, @fgp, NOW())
ON CONFLICT (id)
DO UPDATE SET version = EXCLUDED.version, etag = EXCLUDED.etag, fgp = EXCLUDED.fgp, updated_at = EXCLUDED.updated_at;
";
            upsert.Parameters.AddWithValue("version", nextVersion);
            upsert.Parameters.AddWithValue("etag", etag);
            upsert.Parameters.AddWithValue("fgp", fgp);
            await upsert.ExecuteNonQueryAsync(cancellationToken);
        }

        await tx.CommitAsync(cancellationToken);
        return new FgpRow(etag, nextVersion, fgp);
    }
}

sealed class WebSocketHub
{
    private readonly object _gate = new();
    private readonly Dictionary<string, WebSocket> _sockets = new();

    public string Add(WebSocket socket)
    {
        var id = Guid.NewGuid().ToString("n");
        lock (_gate)
        {
            _sockets[id] = socket;
        }

        return id;
    }

    public void Remove(string id)
    {
        lock (_gate)
        {
            _sockets.Remove(id);
        }
    }

    public async Task BroadcastAsync(string json, CancellationToken cancellationToken)
    {
        List<WebSocket> targets;
        lock (_gate)
        {
            targets = _sockets.Values.ToList();
        }

        foreach (var socket in targets)
        {
            if (socket.State != WebSocketState.Open)
            {
                continue;
            }

            await SendAsync(socket, json, cancellationToken);
        }
    }

    public Task SendAsync(WebSocket socket, string json, CancellationToken cancellationToken)
    {
        var bytes = Encoding.UTF8.GetBytes(json);
        return socket.SendAsync(bytes, WebSocketMessageType.Text, true, cancellationToken);
    }
}

static class NitroMessage
{
    public static string Latest(string etag, long version, string fgp)
        => JsonSerializer.Serialize(new
        {
            type = "LATEST",
            etag,
            version,
            fgpBase64 = Convert.ToBase64String(Encoding.UTF8.GetBytes(fgp)),
        });

    public static string FgpUpdated(string etag, long version, string fgp)
        => JsonSerializer.Serialize(new
        {
            type = "FGP_UPDATED",
            etag,
            version,
            fgpBase64 = Convert.ToBase64String(Encoding.UTF8.GetBytes(fgp)),
        });

    public static string Error(string message)
        => JsonSerializer.Serialize(new { type = "ERROR", message });
}
