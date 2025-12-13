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

builder.Services
    .AddFusionGatewayServer()
    .ConfigureFromFile("gateway.fgp");

var app = builder.Build();

app.UseCors();
app.UseWebSockets();
app.MapGraphQL();

app.Run();
