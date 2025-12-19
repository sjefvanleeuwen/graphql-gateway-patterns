using Common.Auth;
using Microsoft.Extensions.Options;

namespace Gateway.Auth;

/// <summary>
/// Endpoints for viewing and managing cost statistics.
/// </summary>
public static class CostEndpoints
{
    public static void MapCostEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/cost")
            .WithTags("Cost Management");

        // Get current user's cost statistics with pricing
        group.MapGet("/me", (
            HttpContext context,
            ICostStorageService costStorage,
            IOptionsMonitor<CostLimitConfig> config,
            IOptionsMonitor<CostPricingConfig> pricingConfig) =>
        {
            var userId = context.User.GetCostTrackingUserId();
            var stats = costStorage.GetUserStatistics(userId);
            var maxCost = context.User.GetMaxCostForUser(config.CurrentValue);
            
            // Update max cost based on current role
            stats.MaxCostPerWindow = maxCost;
            
            // Get account tier from claims or default to Normal
            var accountTier = context.User.FindFirst("accountTier")?.Value ?? "Normal";
            var pricing = pricingConfig.CurrentValue;
            
            // Get tier pricing
            var tierPricing = pricing.TierPricing.GetValueOrDefault(accountTier, 
                new TierPricing { MonthlyFee = 29.99, CostMultiplier = 0.001 });
            
            // Calculate cost in euros
            var costInEuros = stats.TotalCost * tierPricing.CostMultiplier;
            
            // Group requests by day for the last 30 days
            var dailyCosts = stats.RecentRequests
                .GroupBy(r => r.Timestamp.Date)
                .Select(g => new
                {
                    date = g.Key,
                    totalCost = g.Sum(r => r.CalculatedCost),
                    requestCount = g.Count(),
                    costInEuros = g.Sum(r => r.CalculatedCost) * tierPricing.CostMultiplier
                })
                .OrderBy(d => d.date)
                .ToList();
            
            return Results.Ok(new
            {
                userId = stats.UserId,
                userName = stats.UserName,
                accountTier,
                currentWindow = new
                {
                    start = stats.WindowStart,
                    end = stats.WindowEnd,
                    totalCost = stats.TotalCost,
                    maxCost = stats.MaxCostPerWindow,
                    remainingCost = stats.RemainingCost,
                    requestCount = stats.RequestCount,
                    isOverBudget = stats.IsOverBudget,
                    costInEuros
                },
                pricing = new
                {
                    monthlyFee = tierPricing.MonthlyFee,
                    costMultiplier = tierPricing.CostMultiplier,
                    costPerRequest = stats.RequestCount > 0 
                        ? costInEuros / stats.RequestCount 
                        : 0
                },
                dailyCosts,
                recentRequests = stats.RecentRequests.TakeLast(20).Select(r => new
                {
                    timestamp = r.Timestamp,
                    operationName = r.OperationName,
                    fieldCount = r.FieldCount,
                    depth = r.Depth,
                    cost = r.CalculatedCost,
                    costInEuros = r.CalculatedCost * tierPricing.CostMultiplier,
                    wasAllowed = r.WasAllowed
                })
            });
        })
        .WithName("GetMyCostStatistics")
        .WithDescription("Get cost statistics with pricing for the current user");

        // Get all users' cost statistics (admin only)
        group.MapGet("/all", (
            HttpContext context,
            ICostStorageService costStorage) =>
        {
            // Check if user is admin
            if (!context.User.IsInRole("Admin"))
            {
                return Results.Forbid();
            }
            
            var allStats = costStorage.GetAllStatistics()
                .Select(stats => new
                {
                    userId = stats.UserId,
                    userName = stats.UserName,
                    totalCost = stats.TotalCost,
                    maxCost = stats.MaxCostPerWindow,
                    remainingCost = stats.RemainingCost,
                    requestCount = stats.RequestCount,
                    isOverBudget = stats.IsOverBudget,
                    windowEnd = stats.WindowEnd
                });
            
            return Results.Ok(new
            {
                users = allStats,
                totalUsers = allStats.Count()
            });
        })
        .WithName("GetAllCostStatistics")
        .WithDescription("Get cost statistics for all users (admin only)")
        .RequireAuthorization("AdminOnly");

        // Clear current user's statistics
        group.MapDelete("/me", (
            HttpContext context,
            ICostStorageService costStorage) =>
        {
            var userId = context.User.GetCostTrackingUserId();
            costStorage.ClearUserStatistics(userId);
            return Results.Ok(new { message = "Cost statistics cleared", userId });
        })
        .WithName("ClearMyCostStatistics")
        .WithDescription("Clear cost statistics for the current user");

        // Clear all statistics (admin only)
        group.MapDelete("/all", (
            HttpContext context,
            ICostStorageService costStorage) =>
        {
            if (!context.User.IsInRole("Admin"))
            {
                return Results.Forbid();
            }
            
            costStorage.ClearAllStatistics();
            return Results.Ok(new { message = "All cost statistics cleared" });
        })
        .WithName("ClearAllCostStatistics")
        .WithDescription("Clear cost statistics for all users (admin only)")
        .RequireAuthorization("AdminOnly");

        // Get cost configuration (read-only)
        group.MapGet("/config", (IOptionsMonitor<CostLimitConfig> config) =>
        {
            var c = config.CurrentValue;
            return Results.Ok(new
            {
                windowSeconds = c.WindowSeconds,
                defaultMaxCost = c.DefaultMaxCost,
                anonymousMaxCost = c.AnonymousMaxCost,
                roleMultipliers = c.RoleMultipliers,
                costPerField = c.CostPerField,
                costPerDepthLevel = c.CostPerDepthLevel,
                mutationMultiplier = c.MutationMultiplier,
                listFieldMultiplier = c.ListFieldMultiplier,
                maxDepth = c.MaxDepth,
                maxFields = c.MaxFields
            });
        })
        .WithName("GetCostConfig")
        .WithDescription("Get the current cost limit configuration");
    }
}
