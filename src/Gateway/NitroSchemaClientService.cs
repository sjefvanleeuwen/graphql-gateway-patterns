using System.Net.WebSockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Gateway;

public sealed class NitroSchemaClientService : BackgroundService, INitroSchemaPublisher
{
    private readonly ILogger<NitroSchemaClientService> _logger;
    private readonly IConfiguration _config;
    private readonly IHostEnvironment _env;
    private readonly string _fgpPath;

    private readonly SemaphoreSlim _sendGate = new(1, 1);
    private ClientWebSocket? _socket;

    public NitroSchemaClientService(ILogger<NitroSchemaClientService> logger, IConfiguration config, IHostEnvironment env)
    {
        _logger = logger;
        _config = config;
        _env = env;
        _fgpPath = System.IO.Path.Combine(_env.ContentRootPath, "gateway.fgp");
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var url = _config["Nitro:WsUrl"] ?? Environment.GetEnvironmentVariable("NITRO_SCHEMA_WS");
        if (string.IsNullOrWhiteSpace(url))
        {
            _logger.LogWarning("Nitro WS URL not configured (Nitro:WsUrl / NITRO_SCHEMA_WS). Gateway will not auto-update gateway.fgp.");
            return;
        }

        var instanceId = Guid.NewGuid().ToString("n");

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                using var socket = new ClientWebSocket();
                _socket = socket;

                _logger.LogInformation("Connecting to Nitro at {Url}", url);
                await socket.ConnectAsync(new Uri(url), stoppingToken);

                await SendJsonAsync(socket, new
                {
                    type = "HELLO",
                    gatewayInstanceId = instanceId,
                    currentEtag = GetCurrentEtagOrNull(),
                }, stoppingToken);

                await ReceiveLoopAsync(socket, stoppingToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Nitro connection failed; retrying soon");
                await Task.Delay(TimeSpan.FromSeconds(3), stoppingToken);
            }
            finally
            {
                _socket = null;
            }
        }
    }

    public async Task PublishAsync(string fgpBase64, string token, CancellationToken cancellationToken)
    {
        var socket = _socket;
        if (socket is null || socket.State != WebSocketState.Open)
        {
            throw new InvalidOperationException("Nitro WS is not connected");
        }

        await _sendGate.WaitAsync(cancellationToken);
        try
        {
            await SendJsonAsync(socket, new
            {
                type = "PUBLISH",
                token,
                fgpBase64,
            }, cancellationToken);
        }
        finally
        {
            _sendGate.Release();
        }
    }

    private async Task ReceiveLoopAsync(ClientWebSocket socket, CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested && socket.State == WebSocketState.Open)
        {
            var json = await ReceiveTextMessageAsync(socket, maxMessageBytes: 100 * 1024 * 1024, stoppingToken);
            if (json is null)
            {
                break;
            }

            await HandleInboundAsync(json, stoppingToken);
        }
    }

    private static async Task<string?> ReceiveTextMessageAsync(ClientWebSocket socket, int maxMessageBytes, CancellationToken cancellationToken)
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

    private async Task HandleInboundAsync(string json, CancellationToken cancellationToken)
    {
        using var doc = JsonDocument.Parse(json);
        if (!doc.RootElement.TryGetProperty("type", out var typeEl))
        {
            return;
        }

        var type = typeEl.GetString();
        if (type is not ("LATEST" or "FGP_UPDATED"))
        {
            return;
        }

        if (!doc.RootElement.TryGetProperty("fgpBase64", out var fgpEl))
        {
            return;
        }

        var fgpBase64 = fgpEl.GetString();
        if (string.IsNullOrWhiteSpace(fgpBase64))
        {
            return;
        }

        string fgp;
        try
        {
            fgp = Encoding.UTF8.GetString(Convert.FromBase64String(fgpBase64));
        }
        catch
        {
            return;
        }

        await WriteFgpAtomicallyAsync(fgp, cancellationToken);
    }

    private async Task WriteFgpAtomicallyAsync(string fgp, CancellationToken cancellationToken)
    {
        var dir = System.IO.Path.GetDirectoryName(_fgpPath) ?? _env.ContentRootPath;
        var tmp = System.IO.Path.Combine(dir, "gateway.fgp.tmp");

        await File.WriteAllTextAsync(tmp, fgp, Encoding.UTF8, cancellationToken);
        File.Move(tmp, _fgpPath, overwrite: true);

        _logger.LogInformation("Updated gateway.fgp from Nitro");
    }

    private string? GetCurrentEtagOrNull()
    {
        try
        {
            if (!File.Exists(_fgpPath))
            {
                return null;
            }

            var fgp = File.ReadAllText(_fgpPath, Encoding.UTF8);
            var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(fgp));
            return Convert.ToHexString(bytes).ToLowerInvariant();
        }
        catch
        {
            return null;
        }
    }

    private static Task SendJsonAsync(ClientWebSocket socket, object payload, CancellationToken cancellationToken)
    {
        var json = JsonSerializer.Serialize(payload);
        var bytes = Encoding.UTF8.GetBytes(json);
        return socket.SendAsync(bytes, WebSocketMessageType.Text, true, cancellationToken);
    }
}

public interface INitroSchemaPublisher
{
    Task PublishAsync(string fgpBase64, string token, CancellationToken cancellationToken);
}
