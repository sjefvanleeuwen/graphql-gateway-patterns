using OrdersService;
using OrdersService.Data;
using Wolverine;
using Wolverine.Marten;
using Wolverine.Postgresql;
using Marten;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddSingleton<OrderRepository>();

var connectionString = builder.Configuration.GetConnectionString("postgres");

// Add Marten
builder.Services.AddMarten(opts =>
{
    opts.Connection(connectionString);
});

// Add Wolverine
builder.Host.UseWolverine(opts =>
{
    opts.UsePostgresqlPersistenceAndTransport(connectionString, schema: "transport")
        .AutoProvision();
        
    opts.PublishMessage<Shared.OrderPlaced>().ToPostgresqlQueue("orders");
    opts.ListenToPostgresqlQueue("notifications");
});

builder.Services
    .AddGraphQLServer()
    .AddQueryType<Query>()
    .AddMutationType<Mutation>()
    .AddSubscriptionType<Subscription>()
    .AddInMemorySubscriptions()
    .AddFiltering()
    .AddSorting();

var app = builder.Build();

app.UseWebSockets();
app.MapGraphQL();

app.RunWithGraphQLCommands(args);
