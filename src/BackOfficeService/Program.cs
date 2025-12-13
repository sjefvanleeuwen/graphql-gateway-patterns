using Wolverine;
using Wolverine.Transports.Tcp;

var builder = Host.CreateApplicationBuilder(args);

builder.UseWolverine(opts =>
{
    opts.ListenAtPort(5556);
    opts.PublishMessage<Shared.OrderProcessed>().ToPort(5555);
});

var host = builder.Build();
host.Run();
