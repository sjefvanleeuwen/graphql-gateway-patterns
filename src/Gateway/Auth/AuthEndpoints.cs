using Common.Auth;
using Microsoft.AspNetCore.Mvc;

namespace Gateway.Auth;

public static class AuthEndpoints
{
    public static void MapAuthEndpoints(this WebApplication app)
    {
        app.MapPost("/auth/login", Login);
        app.MapGet("/auth/test-tokens", GetTestTokens);
    }

    /// <summary>
    /// Login endpoint - In production, validate against a user store
    /// For demo purposes, accepts predefined users
    /// </summary>
    private static IResult Login([FromBody] LoginRequest request, [FromServices] TokenService tokenService)
    {
        // Demo users - In production, validate against a database
        var users = new Dictionary<string, (string Password, string[] Roles)>
        {
            ["admin"] = ("admin123", new[] { "Admin" }),
            ["user"] = ("user123", new[] { "User" }),
            ["viewer"] = ("viewer123", new[] { "Viewer" }),
            ["poweruser"] = ("power123", new[] { "User", "Viewer" })
        };

        if (!users.TryGetValue(request.Username.ToLower(), out var userInfo))
        {
            return Results.Unauthorized();
        }

        if (userInfo.Password != request.Password)
        {
            return Results.Unauthorized();
        }

        var token = tokenService.GenerateToken(
            userId: Guid.NewGuid().ToString(),
            username: request.Username,
            roles: userInfo.Roles
        );

        return Results.Ok(new LoginResponse(token, userInfo.Roles, DateTime.UtcNow.AddMinutes(60)));
    }

    /// <summary>
    /// Returns test tokens for each role - useful for development/testing
    /// </summary>
    private static IResult GetTestTokens([FromServices] TokenService tokenService)
    {
        var tokens = new
        {
            AdminToken = new
            {
                Token = tokenService.GenerateToken("1", "admin", new[] { "Admin" }),
                Roles = new[] { "Admin" },
                Description = "Full access to all queries, mutations, and fields"
            },
            UserToken = new
            {
                Token = tokenService.GenerateToken("2", "user", new[] { "User" }),
                Roles = new[] { "User" },
                Description = "Can query entities, place orders, view prices"
            },
            ViewerToken = new
            {
                Token = tokenService.GenerateToken("3", "viewer", new[] { "Viewer" }),
                Roles = new[] { "Viewer" },
                Description = "Read-only access to public data (no prices, limited fields)"
            }
        };

        return Results.Ok(tokens);
    }
}

public record LoginRequest(string Username, string Password);
public record LoginResponse(string Token, string[] Roles, DateTime ExpiresAt);
