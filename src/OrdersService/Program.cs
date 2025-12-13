using OrdersService;
using OrdersService.Data;
using Wolverine;
using Wolverine.Transports.Tcp;
using Wolverine.AzureServiceBus;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddSingleton<OrderRepository>();

// Add Wolverine
builder.Host.UseWolverine(opts =>
{
    var connectionString = builder.Configuration.GetConnectionString("messaging");
    
    if (!string.IsNullOrEmpty(connectionString))
    {
        // Cloud Mode: Azure Service Bus
        opts.UseAzureServiceBus(connectionString).AutoProvision();
        opts.PublishMessage<Shared.OrderPlaced>().ToAzureServiceBusQueue("orders");
    }
    else
    {
        // Local Mode: TCP
        // In Docker, "localhost" refers to the container itself.
        // We need to send messages to the "backoffice" container.
        var backofficeHost = builder.Configuration["Wolverine:BackOfficeHost"] ?? "localhost";
        
        // Listen on all interfaces (0.0.0.0)
        opts.ListenForMessagesFrom(new Uri("tcp://0.0.0.0:5555"));

        opts.PublishMessage<Shared.OrderPlaced>().To(new Uri($"tcp://{backofficeHost}:5556"));
    }
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
