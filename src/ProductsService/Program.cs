using ProductsService;

var builder = WebApplication.CreateBuilder(args);

builder.Services
    .AddGraphQLServer()
    .AddQueryType<Query>()
    .AddGlobalObjectIdentification()
    .AddFiltering()
    .AddSorting();

var app = builder.Build();

app.MapGraphQL();

app.RunWithGraphQLCommands(args);
