using Wolverine;
using Wolverine.Marten;
using Wolverine.Postgresql;
using Wolverine.Postgresql.Transport;
using Marten;

var builder = Host.CreateApplicationBuilder(args);

var connectionString = builder.Configuration.GetConnectionString("postgres");

builder.Services.AddMarten(opts =>
{
    opts.Connection(connectionString);
});

builder.UseWolverine(opts =>
{
    opts.UsePostgresqlPersistenceAndTransport(connectionString, schema: "transport")
        .AutoProvision();

    opts.ListenToPostgresqlQueue("orders");
    opts.PublishMessage<Shared.OrderProcessed>().ToPostgresqlQueue("notifications");
});

var host = builder.Build();
host.Run();
