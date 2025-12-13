using OrdersService;
using OrdersService.Data;
using Wolverine;
using Wolverine.Transports.Tcp;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddSingleton<OrderRepository>();

// Add Wolverine
builder.Host.UseWolverine(opts =>
{
    opts.ListenAtPort(5555);
    opts.PublishMessage<Shared.OrderPlaced>().ToPort(5556);
});

builder.Services
    .AddGraphQLServer()
    .AddQueryType<Query>()
    .AddMutationType<Mutation>()
    .AddFiltering()
    .AddSorting();

var app = builder.Build();

app.MapGraphQL();

app.RunWithGraphQLCommands(args);
