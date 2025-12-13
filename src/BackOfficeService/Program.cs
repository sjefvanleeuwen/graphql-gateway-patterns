using Wolverine;
using Wolverine.Transports.Tcp;
using Wolverine.AzureServiceBus;

var builder = Host.CreateApplicationBuilder(args);

builder.UseWolverine(opts =>
{
    var connectionString = builder.Configuration.GetConnectionString("messaging");

    if (!string.IsNullOrEmpty(connectionString))
    {
        // Cloud Mode: Azure Service Bus
        opts.UseAzureServiceBus(connectionString).AutoProvision();
        opts.ListenToAzureServiceBusQueue("orders");
    }
    else
    {
        // Local Mode: TCP
        var ordersHost = builder.Configuration["Wolverine:OrdersHost"] ?? "localhost";

        // Listen on all interfaces (0.0.0.0)
        opts.ListenForMessagesFrom(new Uri("tcp://0.0.0.0:5556"));

        opts.PublishMessage<Shared.OrderProcessed>().To(new Uri($"tcp://{ordersHost}:5555"));
    }
});

var host = builder.Build();
host.Run();
