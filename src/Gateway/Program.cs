var builder = WebApplication.CreateBuilder(args);

builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(builder =>
    {
        builder.WithOrigins("http://localhost:5173")
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
