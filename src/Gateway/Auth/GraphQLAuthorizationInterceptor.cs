using System.Security.Claims;
using HotChocolate.AspNetCore;
using HotChocolate.Execution;
using HotChocolate.Language;
using Microsoft.AspNetCore.Authorization;
using Microsoft.Extensions.Options;

namespace Gateway.Auth;

/// <summary>
/// HTTP request interceptor that enforces authorization policies at the Gateway level.
/// This approach avoids conflicts with HotChocolate's @authorize directive in Fusion.
/// 
/// Authorization rules are defined in appsettings.json under "FieldAuthorization".
/// </summary>
public class GraphQLAuthorizationInterceptor : DefaultHttpRequestInterceptor
{
    private readonly IAuthorizationService _authorizationService;
    private readonly IOptionsMonitor<FieldAuthorizationConfig> _config;
    private readonly ILogger<GraphQLAuthorizationInterceptor> _logger;

    public GraphQLAuthorizationInterceptor(
        IAuthorizationService authorizationService,
        IOptionsMonitor<FieldAuthorizationConfig> config,
        ILogger<GraphQLAuthorizationInterceptor> logger)
    {
        _authorizationService = authorizationService;
        _config = config;
        _logger = logger;
    }

    public override async ValueTask OnCreateAsync(
        HttpContext context,
        IRequestExecutor requestExecutor,
        OperationRequestBuilder requestBuilder,
        CancellationToken cancellationToken)
    {
        // Let the base class do its work first (sets up context, etc.)
        await base.OnCreateAsync(context, requestExecutor, requestBuilder, cancellationToken);

        // Get the GraphQL request from the context
        var request = context.Items["HotChocolate.Execution.QueryRequest"] as IOperationRequest;
        
        // Parse the query to find which fields are being accessed
        var query = context.Request.Query["query"].FirstOrDefault() 
            ?? await GetQueryFromBody(context);
        
        if (string.IsNullOrEmpty(query))
        {
            return;
        }

        // Parse and check authorization
        try
        {
            var document = Utf8GraphQLParser.Parse(query);
            var violations = await CheckAuthorizationAsync(context, document);
            
            if (violations.Count > 0)
            {
                // Store violations in context for the error handler
                context.Items["AuthorizationViolations"] = violations;
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to parse GraphQL query for authorization check");
        }
    }

    private async Task<string?> GetQueryFromBody(HttpContext context)
    {
        // Body might have already been read, try to get from items
        if (context.Items.TryGetValue("GraphQL.Query", out var queryObj) && queryObj is string query)
        {
            return query;
        }
        return null;
    }

    private async Task<List<AuthorizationViolation>> CheckAuthorizationAsync(
        HttpContext context, 
        DocumentNode document)
    {
        var violations = new List<AuthorizationViolation>();
        var user = context.User;
        var config = _config.CurrentValue;

        foreach (var definition in document.Definitions)
        {
            if (definition is OperationDefinitionNode operation)
            {
                await CheckSelectionsAsync(
                    user,
                    config,
                    operation.SelectionSet,
                    operation.Operation.ToString().ToLowerInvariant(),
                    violations);
            }
        }

        return violations;
    }

    private async Task CheckSelectionsAsync(
        ClaimsPrincipal user,
        FieldAuthorizationConfig config,
        SelectionSetNode? selectionSet,
        string parentPath,
        List<AuthorizationViolation> violations)
    {
        if (selectionSet == null) return;

        foreach (var selection in selectionSet.Selections)
        {
            if (selection is FieldNode field)
            {
                var fieldName = field.Name.Value;
                var fieldPath = $"{parentPath}.{fieldName}";

                // Check if this field has a policy requirement
                if (config.Fields.TryGetValue(fieldPath, out var policyName))
                {
                    var result = await _authorizationService.AuthorizeAsync(user, policyName);
                    
                    if (!result.Succeeded)
                    {
                        _logger.LogWarning(
                            "Authorization failed for field '{FieldPath}' with policy '{Policy}' for user '{User}'",
                            fieldPath, policyName, user.Identity?.Name ?? "anonymous");
                        
                        violations.Add(new AuthorizationViolation(fieldPath, policyName));
                    }
                    else
                    {
                        _logger.LogDebug(
                            "Authorization succeeded for field '{FieldPath}' with policy '{Policy}'",
                            fieldPath, policyName);
                    }
                }

                // Recursively check nested selections
                if (field.SelectionSet != null)
                {
                    await CheckSelectionsAsync(user, config, field.SelectionSet, fieldPath, violations);
                }
            }
        }
    }
}

/// <summary>
/// Configuration for field-level authorization.
/// Maps GraphQL field paths to authorization policy names.
/// </summary>
public class FieldAuthorizationConfig
{
    /// <summary>
    /// Maps field paths (e.g., "query.orders", "mutation.placeOrder") to policy names.
    /// </summary>
    public Dictionary<string, string> Fields { get; set; } = new();
}

/// <summary>
/// Represents an authorization violation.
/// </summary>
public record AuthorizationViolation(string FieldPath, string PolicyName);
