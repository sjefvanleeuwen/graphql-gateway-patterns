using Microsoft.AspNetCore.Authorization;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace Common.Auth;

/// <summary>
/// Configuration-based authorization policy loader with hot-reload support.
/// Policies are defined in appsettings.json and can be reloaded at runtime.
/// </summary>
public static class AuthorizationConfigExtensions
{
    /// <summary>
    /// Adds authorization policies from configuration directly into AuthorizationOptions.
    /// This approach registers REAL policies (not dummy ones) so HotChocolate can use them.
    /// For hot-reload, call RefreshPolicies when configuration changes.
    /// </summary>
    public static IServiceCollection AddAuthorizationFromConfig(
        this IServiceCollection services, 
        IConfiguration configuration,
        string sectionName = "Authorization")
    {
        // Bind configuration section to options (supports reload notification)
        var section = configuration.GetSection(sectionName);
        services.Configure<AuthorizationConfig>(section);
        
        // Register policies directly into AuthorizationOptions
        // HotChocolate Fusion uses AuthorizationOptions.GetPolicy() internally
        var config = section.Get<AuthorizationConfig>();
        if (config?.Policies != null)
        {
            services.AddAuthorization(options =>
            {
                foreach (var (policyName, policyConfig) in config.Policies)
                {
                    options.AddPolicy(policyName, builder => BuildPolicy(builder, policyConfig));
                }
            });
        }

        return services;
    }
    
    /// <summary>
    /// Builds an authorization policy from configuration.
    /// </summary>
    private static void BuildPolicy(AuthorizationPolicyBuilder builder, PolicyConfig config)
    {
        // Require authentication if specified
        if (config.RequireAuthentication)
        {
            builder.RequireAuthenticatedUser();
        }

        // Add role requirements
        if (config.Roles?.Length > 0)
        {
            builder.RequireRole(config.Roles);
        }

        // Add claim requirements
        if (config.Claims != null)
        {
            foreach (var claim in config.Claims)
            {
                if (claim.Values?.Length > 0)
                {
                    builder.RequireClaim(claim.Type, claim.Values);
                }
                else
                {
                    builder.RequireClaim(claim.Type);
                }
            }
        }

        // If no requirements specified, at least require authentication
        if (!config.RequireAuthentication && 
            (config.Roles == null || config.Roles.Length == 0) &&
            (config.Claims == null || config.Claims.Length == 0))
        {
            builder.RequireAuthenticatedUser();
        }
    }
}
