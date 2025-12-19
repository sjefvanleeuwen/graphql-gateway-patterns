namespace Common.Auth;

/// <summary>
/// Root configuration for authorization policies.
/// Bind to "Authorization" section in appsettings.json.
/// </summary>
public class AuthorizationConfig
{
    /// <summary>
    /// Dictionary of policy name to policy configuration.
    /// </summary>
    public Dictionary<string, PolicyConfig> Policies { get; set; } = new();
}

/// <summary>
/// Configuration for a single authorization policy.
/// </summary>
public class PolicyConfig
{
    /// <summary>
    /// If true, user must be authenticated (any role).
    /// </summary>
    public bool RequireAuthentication { get; set; }

    /// <summary>
    /// Roles that satisfy this policy (OR logic - any role matches).
    /// </summary>
    public string[]? Roles { get; set; }

    /// <summary>
    /// Claims that must be present.
    /// </summary>
    public ClaimConfig[]? Claims { get; set; }
}

/// <summary>
/// Configuration for a claim requirement.
/// </summary>
public class ClaimConfig
{
    /// <summary>
    /// The claim type (e.g., "subscription", "department").
    /// </summary>
    public string Type { get; set; } = string.Empty;

    /// <summary>
    /// Allowed values for the claim (OR logic - any value matches).
    /// If empty, just checks claim exists.
    /// </summary>
    public string[]? Values { get; set; }
}
