using Wolverine;
using Wolverine.Marten;
using Wolverine.Postgresql;
using Wolverine.Postgresql.Transport;
using Marten;

var builder = WebApplication.CreateBuilder(args);

var connectionString = builder.Configuration.GetConnectionString("postgres");

builder.Services.AddMarten(opts =>
{
    opts.Connection(connectionString);
});

builder.Host.UseWolverine(opts =>
{
    opts.UsePostgresqlPersistenceAndTransport(connectionString, schema: "transport")
        .AutoProvision();

    opts.ListenToPostgresqlQueue("orders");
    opts.PublishMessage<Shared.OrderProcessed>().ToPostgresqlQueue("notifications");
});

var app = builder.Build();

app.MapGet("/health", () => "Healthy");

app.Run();
