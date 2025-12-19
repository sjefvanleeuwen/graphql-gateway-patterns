using System.Security.Claims;
using System.Text.Json;
using System.Text.RegularExpressions;
using Common.Auth;
using Microsoft.AspNetCore.Authorization;
using Microsoft.Extensions.Options;

namespace Gateway.Auth;

/// <summary>
/// Middleware that enforces GraphQL authorization and cost-based rate limiting at the Gateway level.
/// Checks field-level policies and tracks query costs before the request reaches HotChocolate.
/// 
/// This approach:
/// 1. Parses the incoming GraphQL query
/// 2. Calculates the query cost/complexity
/// 3. Checks if user has budget remaining
/// 4. Checks authorization policies for each field
/// 5. Records the cost and returns appropriate response
/// </summary>
public class GraphQLAuthorizationMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<GraphQLAuthorizationMiddleware> _logger;

    public GraphQLAuthorizationMiddleware(RequestDelegate next, ILogger<GraphQLAuthorizationMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(
        HttpContext context,
        IAuthorizationService authorizationService,
        IOptionsMonitor<FieldAuthorizationConfig> authConfig,
        IOptionsMonitor<CostLimitConfig> costConfig,
        ICostStorageService costStorage)
    {
        // Only intercept GraphQL requests
        if (!context.Request.Path.StartsWithSegments("/graphql"))
        {
            await _next(context);
            return;
        }

        // Skip for GET requests (typically introspection from playground)
        if (context.Request.Method == "GET")
        {
            await _next(context);
            return;
        }

        // Enable buffering so we can read the body multiple times
        context.Request.EnableBuffering();

        try
        {
            // Read the request body
            using var reader = new StreamReader(context.Request.Body, leaveOpen: true);
            var body = await reader.ReadToEndAsync();
            context.Request.Body.Position = 0; // Reset for HotChocolate

            if (string.IsNullOrEmpty(body))
            {
                await _next(context);
                return;
            }

            // Parse the GraphQL request
            var graphqlRequest = JsonSerializer.Deserialize<GraphQLRequest>(body, new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            });

            if (graphqlRequest?.Query == null)
            {
                await _next(context);
                return;
            }

            var config = costConfig.CurrentValue;
            var userId = context.User.GetCostTrackingUserId();
            var maxCost = context.User.GetMaxCostForUser(config);
            
            // Update user's max cost based on role
            var userStats = costStorage.GetUserStatistics(userId);
            userStats.MaxCostPerWindow = maxCost;
            userStats.UserName = context.User.Identity?.Name;

            // Calculate query cost
            var costResult = CalculateQueryCost(graphqlRequest.Query, graphqlRequest.OperationName, config);
            
            // Check if query exceeds complexity limits
            if (costResult.ExceedsLimits)
            {
                _logger.LogWarning(
                    "Query complexity exceeded for user '{User}': {Reason}",
                    userId, costResult.LimitExceededReason);
                
                await ReturnCostError(context, costResult, "QUERY_TOO_COMPLEX");
                return;
            }

            // Check if user can afford this query
            if (!costStorage.CanAffordCost(userId, costResult.TotalCost))
            {
                var stats = costStorage.GetUserStatistics(userId);
                _logger.LogWarning(
                    "Rate limit exceeded for user '{User}'. Cost: {Cost}, Remaining: {Remaining}, Window resets: {Reset}",
                    userId, costResult.TotalCost, stats.RemainingCost, stats.WindowEnd);
                
                await ReturnRateLimitError(context, stats, costResult.TotalCost);
                return;
            }

            // Check authorization
            var violations = await CheckAuthorizationAsync(
                context.User,
                graphqlRequest.Query,
                authorizationService,
                authConfig.CurrentValue);

            if (violations.Count > 0)
            {
                _logger.LogWarning(
                    "Authorization denied for user '{User}'. Violations: {Violations}",
                    userId,
                    string.Join(", ", violations.Select(v => $"{v.FieldPath}:{v.PolicyName}")));

                // Record the failed request (still costs something)
                var entry = new CostEntry
                {
                    OperationName = graphqlRequest.OperationName,
                    FieldCount = costResult.FieldCount,
                    Depth = costResult.MaxDepth,
                    CalculatedCost = Math.Max(1, costResult.TotalCost / 10), // Partial cost for denied requests
                    WasAllowed = false
                };
                costStorage.RecordCost(userId, entry, config);

                await ReturnAuthorizationError(context, violations);
                return;
            }

            // Record the successful cost
            var successEntry = new CostEntry
            {
                OperationName = graphqlRequest.OperationName,
                FieldCount = costResult.FieldCount,
                Depth = costResult.MaxDepth,
                CalculatedCost = costResult.TotalCost,
                WasAllowed = true
            };
            costStorage.RecordCost(userId, successEntry, config);

            // Add cost info to response headers
            var updatedStats = costStorage.GetUserStatistics(userId);
            context.Response.OnStarting(() =>
            {
                context.Response.Headers["X-Cost-Total"] = costResult.TotalCost.ToString();
                context.Response.Headers["X-Cost-Remaining"] = updatedStats.RemainingCost.ToString();
                context.Response.Headers["X-Cost-Reset"] = updatedStats.WindowEnd.ToString("O");
                return Task.CompletedTask;
            });

            _logger.LogDebug(
                "Request allowed for user '{User}'. Cost: {Cost}, Remaining: {Remaining}",
                userId, costResult.TotalCost, updatedStats.RemainingCost);
        }
        catch (JsonException ex)
        {
            _logger.LogDebug(ex, "Failed to parse GraphQL request body");
            // Let HotChocolate handle malformed requests
        }

        await _next(context);
    }

    private CostCalculationResult CalculateQueryCost(string query, string? operationName, CostLimitConfig config)
    {
        var result = new CostCalculationResult();
        
        // Determine if it's a mutation
        result.IsMutation = query.Contains("mutation", StringComparison.OrdinalIgnoreCase);
        
        // Count fields (simplified - counts field-like patterns)
        var fieldMatches = Regex.Matches(query, @"\b(\w+)\s*[({:]", RegexOptions.IgnoreCase);
        result.FieldCount = fieldMatches.Count;
        
        // Calculate depth (count nested braces)
        int maxDepth = 0;
        int currentDepth = 0;
        foreach (char c in query)
        {
            if (c == '{')
            {
                currentDepth++;
                maxDepth = Math.Max(maxDepth, currentDepth);
            }
            else if (c == '}')
            {
                currentDepth--;
            }
        }
        result.MaxDepth = maxDepth;
        
        // Check limits
        if (result.MaxDepth > config.MaxDepth)
        {
            result.ExceedsLimits = true;
            result.LimitExceededReason = $"Query depth {result.MaxDepth} exceeds maximum {config.MaxDepth}";
        }
        
        if (result.FieldCount > config.MaxFields)
        {
            result.ExceedsLimits = true;
            result.LimitExceededReason = $"Field count {result.FieldCount} exceeds maximum {config.MaxFields}";
        }
        
        // Calculate total cost
        long baseCost = result.FieldCount * config.CostPerField;
        long depthCost = result.MaxDepth * config.CostPerDepthLevel;
        
        result.TotalCost = baseCost + depthCost;
        
        // Apply mutation multiplier
        if (result.IsMutation)
        {
            result.TotalCost = (long)(result.TotalCost * config.MutationMultiplier);
        }
        
        // Check for list/pagination fields (these are more expensive)
        var listPatterns = new[] { "nodes", "edges", "items", "results", "list" };
        foreach (var pattern in listPatterns)
        {
            if (query.Contains(pattern, StringComparison.OrdinalIgnoreCase))
            {
                result.TotalCost = (long)(result.TotalCost * config.ListFieldMultiplier);
                break;
            }
        }
        
        // Minimum cost of 1
        result.TotalCost = Math.Max(1, result.TotalCost);
        
        return result;
    }

    private async Task<List<AuthorizationViolation>> CheckAuthorizationAsync(
        ClaimsPrincipal user,
        string query,
        IAuthorizationService authorizationService,
        FieldAuthorizationConfig config)
    {
        var violations = new List<AuthorizationViolation>();

        foreach (var (fieldPath, policyName) in config.Fields)
        {
            var parts = fieldPath.Split('.');
            if (parts.Length < 2) continue;

            var operationType = parts[0].ToLowerInvariant();
            var fieldName = parts[1];

            bool isAccessing = false;

            if (operationType == "query")
            {
                isAccessing = QueryContainsField(query, fieldName, isQuery: true);
            }
            else if (operationType == "mutation")
            {
                isAccessing = QueryContainsField(query, fieldName, isQuery: false);
            }

            if (isAccessing)
            {
                var result = await authorizationService.AuthorizeAsync(user, policyName);
                
                if (!result.Succeeded)
                {
                    _logger.LogDebug(
                        "Authorization check failed for '{FieldPath}' with policy '{Policy}'",
                        fieldPath, policyName);
                    violations.Add(new AuthorizationViolation(fieldPath, policyName));
                }
            }
        }

        return violations;
    }

    private bool QueryContainsField(string query, string fieldName, bool isQuery)
    {
        var normalizedQuery = query.ToLowerInvariant();

        if (isQuery)
        {
            var isMutation = normalizedQuery.Contains("mutation");
            var isSubscription = normalizedQuery.Contains("subscription");
            
            if (!isMutation && !isSubscription)
            {
                return ContainsFieldAccess(query, fieldName);
            }
        }
        else
        {
            if (normalizedQuery.Contains("mutation"))
            {
                return ContainsFieldAccess(query, fieldName);
            }
        }

        return false;
    }

    private bool ContainsFieldAccess(string query, string fieldName)
    {
        var patterns = new[]
        {
            $" {fieldName} ",
            $" {fieldName}(",
            $" {fieldName}{{",
            $"\n{fieldName} ",
            $"\n{fieldName}(",
            $"\n{fieldName}{{",
            $"{{{fieldName} ",
            $"{{{fieldName}(",
            $"{{{fieldName}{{",
            $"{{ {fieldName}",
        };

        return patterns.Any(p => query.Contains(p, StringComparison.OrdinalIgnoreCase));
    }

    private async Task ReturnCostError(HttpContext context, CostCalculationResult costResult, string code)
    {
        context.Response.StatusCode = 200;
        context.Response.ContentType = "application/json";
        
        var errorResponse = new
        {
            errors = new[]
            {
                new
                {
                    message = $"Query too complex: {costResult.LimitExceededReason}",
                    extensions = new
                    {
                        code,
                        cost = costResult.TotalCost,
                        fieldCount = costResult.FieldCount,
                        depth = costResult.MaxDepth
                    }
                }
            }
        };

        await context.Response.WriteAsJsonAsync(errorResponse);
    }

    private async Task ReturnRateLimitError(HttpContext context, UserCostStatistics stats, long requestedCost)
    {
        context.Response.StatusCode = 200;
        context.Response.ContentType = "application/json";
        context.Response.Headers["Retry-After"] = ((int)(stats.WindowEnd - DateTime.UtcNow).TotalSeconds).ToString();
        
        var errorResponse = new
        {
            errors = new[]
            {
                new
                {
                    message = "Rate limit exceeded. Please wait before making more requests.",
                    extensions = new
                    {
                        code = "RATE_LIMIT_EXCEEDED",
                        requestedCost,
                        remainingBudget = stats.RemainingCost,
                        totalBudget = stats.MaxCostPerWindow,
                        resetAt = stats.WindowEnd.ToString("O"),
                        retryAfterSeconds = (int)(stats.WindowEnd - DateTime.UtcNow).TotalSeconds
                    }
                }
            }
        };

        await context.Response.WriteAsJsonAsync(errorResponse);
    }

    private async Task ReturnAuthorizationError(HttpContext context, List<AuthorizationViolation> violations)
    {
        context.Response.StatusCode = 200;
        context.Response.ContentType = "application/json";
        
        var errorResponse = new
        {
            errors = violations.Select(v => new
            {
                message = $"Access denied. You don't have permission to access '{v.FieldPath}'.",
                extensions = new
                {
                    code = "AUTH_NOT_AUTHORIZED",
                    policy = v.PolicyName,
                    field = v.FieldPath
                }
            }).ToArray()
        };

        await context.Response.WriteAsJsonAsync(errorResponse);
    }

    private class GraphQLRequest
    {
        public string? Query { get; set; }
        public string? OperationName { get; set; }
        public JsonElement? Variables { get; set; }
    }
}

/// <summary>
/// Extension methods for adding the GraphQL authorization middleware.
/// </summary>
public static class GraphQLAuthorizationMiddlewareExtensions
{
    public static IApplicationBuilder UseGraphQLAuthorization(this IApplicationBuilder app)
    {
        return app.UseMiddleware<GraphQLAuthorizationMiddleware>();
    }
}
