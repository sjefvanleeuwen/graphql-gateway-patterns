using System.Text;
using Common.Auth;
using Gateway.Auth;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;

var builder = WebApplication.CreateBuilder(args);

// Configure JWT Settings
builder.Services.Configure<JwtSettings>(
    builder.Configuration.GetSection(JwtSettings.SectionName));

var jwtSettings = builder.Configuration.GetSection(JwtSettings.SectionName).Get<JwtSettings>() 
    ?? new JwtSettings();

// Add JWT Authentication
builder.Services.AddAuthentication(options =>
{
    options.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
    options.DefaultChallengeScheme = JwtBearerDefaults.AuthenticationScheme;
})
.AddJwtBearer(options =>
{
    options.TokenValidationParameters = new TokenValidationParameters
    {
        ValidateIssuer = true,
        ValidateAudience = true,
        ValidateLifetime = true,
        ValidateIssuerSigningKey = true,
        ValidIssuer = jwtSettings.Issuer,
        ValidAudience = jwtSettings.Audience,
        IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtSettings.SecretKey)),
        ClockSkew = TimeSpan.Zero
    };
});

// Add authorization with policies loaded from configuration
builder.Services.AddAuthorizationFromConfig(builder.Configuration);

// Add field-level authorization configuration
builder.Services.Configure<FieldAuthorizationConfig>(
    builder.Configuration.GetSection("FieldAuthorization"));

// Add cost tracking configuration and services
builder.Services.Configure<CostLimitConfig>(
    builder.Configuration.GetSection("CostLimits"));
builder.Services.Configure<CostPricingConfig>(
    builder.Configuration.GetSection("CostPricing"));
builder.Services.AddSingleton<ICostStorageService, InMemoryCostStorageService>();

// Register Token Service (from Common)
builder.Services.AddSingleton<TokenService>();

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

builder.Services.AddHostedService<Gateway.FusionReloadService>();
builder.Services.AddHostedService<AuthorizationReloadService>();

// Register the "Status" subgraph schema (no authorization needed)
builder.Services
    .AddGraphQLServer("status")
    .AddQueryType(d => d.Name("Query").Field("status").Resolve("Running"))
    .AddSubscriptionType<Gateway.GatewaySubscriptions>()
    .AddType<AuthorizationReloadedMessage>()
    .AddInMemorySubscriptions();

// Fusion Gateway - no .AddAuthorization() to avoid directive conflict
builder.Services
    .AddFusionGatewayServer()
    .ConfigureFromFile("gateway.fgp");

var app = builder.Build();

app.UseCors();
app.UseWebSockets();

// Add authentication first
app.UseAuthentication();
app.UseAuthorization();

// Add GraphQL-level authorization middleware (before HotChocolate)
app.UseGraphQLAuthorization();

// Map authentication endpoints
app.MapAuthEndpoints();

// Map cost management endpoints
app.MapCostEndpoints();

// Map the main Fusion Gateway
app.MapGraphQL();

// Map the local Status subgraph
app.MapGraphQL("/status/graphql", "status");

app.Run();
