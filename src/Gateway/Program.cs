var builder = WebApplication.CreateBuilder(args);

static string[] ParseCommaSeparatedList(string? value)
{
    if (string.IsNullOrWhiteSpace(value))
    {
        return Array.Empty<string>();
    }

    return value
        .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
        .Where(x => !string.IsNullOrWhiteSpace(x))
        .ToArray();
}

var defaultCorsOrigins = new[]
{
    "http://localhost:5173",
    "http://localhost:3000",
    "http://localhost:4999",
};

var configuredCorsOrigins = builder.Configuration
    .GetSection("Cors:AllowedOrigins")
    .Get<string[]>();

var corsOriginsFromEnv = ParseCommaSeparatedList(Environment.GetEnvironmentVariable("CORS_ALLOWED_ORIGINS"));

var allowedCorsOrigins = (corsOriginsFromEnv.Length > 0)
    ? corsOriginsFromEnv
    : (configuredCorsOrigins?.Length > 0 ? configuredCorsOrigins : defaultCorsOrigins);

builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(builder =>
    {
        builder.WithOrigins(allowedCorsOrigins)
               .AllowAnyHeader()
               .AllowAnyMethod();
    });
});

builder.Services.AddHttpClient();

builder.Services.AddHostedService<Gateway.FusionReloadService>();

// Register the "Status" subgraph schema
builder.Services
    .AddGraphQLServer("status")
    .AddQueryType(d => d.Name("Query").Field("status").Resolve("Running"))
    .AddSubscriptionType<Gateway.GatewaySubscriptions>()
    .AddInMemorySubscriptions();

builder.Services
    .AddFusionGatewayServer()
    .ConfigureFromFile("gateway.fgp");

var app = builder.Build();

app.UseCors();
app.UseWebSockets();

// Map the main Fusion Gateway
app.MapGraphQL();

// Map the local Status subgraph
app.MapGraphQL("/status/graphql", "status");

app.Run();
