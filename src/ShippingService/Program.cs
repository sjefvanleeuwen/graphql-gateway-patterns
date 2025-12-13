using ShippingService;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services
    .AddGraphQLServer()
    .AddQueryType<Query>()
    .AddFiltering()
    .AddSorting();

var app = builder.Build();

// Configure the HTTP request pipeline.
app.MapGraphQL();

app.RunWithGraphQLCommands(args);
