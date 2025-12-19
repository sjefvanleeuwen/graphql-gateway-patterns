namespace Common.Auth;

/// <summary>
/// Represents the cost statistics for a user.
/// Tracks query complexity/cost over time for rate limiting.
/// </summary>
public class UserCostStatistics
{
    public string UserId { get; set; } = string.Empty;
    public string? UserName { get; set; }
    
    /// <summary>
    /// Total accumulated cost for the current window.
    /// </summary>
    public long TotalCost { get; set; }
    
    /// <summary>
    /// Number of requests in the current window.
    /// </summary>
    public int RequestCount { get; set; }
    
    /// <summary>
    /// When the current cost window started.
    /// </summary>
    public DateTime WindowStart { get; set; } = DateTime.UtcNow;
    
    /// <summary>
    /// When the window expires and costs reset.
    /// </summary>
    public DateTime WindowEnd { get; set; }
    
    /// <summary>
    /// Maximum cost allowed in the window.
    /// </summary>
    public long MaxCostPerWindow { get; set; }
    
    /// <summary>
    /// Remaining cost budget in the current window.
    /// </summary>
    public long RemainingCost => Math.Max(0, MaxCostPerWindow - TotalCost);
    
    /// <summary>
    /// Whether the user has exceeded their cost budget.
    /// </summary>
    public bool IsOverBudget => TotalCost >= MaxCostPerWindow;
    
    /// <summary>
    /// History of recent requests with their costs.
    /// </summary>
    public List<CostEntry> RecentRequests { get; set; } = new();
}

/// <summary>
/// Represents a single request's cost entry.
/// </summary>
public class CostEntry
{
    public DateTime Timestamp { get; set; } = DateTime.UtcNow;
    public string? OperationName { get; set; }
    public int FieldCount { get; set; }
    public int Depth { get; set; }
    public long CalculatedCost { get; set; }
    public bool WasAllowed { get; set; }
}

/// <summary>
/// Configuration for cost-based rate limiting.
/// </summary>
public class CostLimitConfig
{
    /// <summary>
    /// Window duration in seconds. Default: 60 (1 minute).
    /// </summary>
    public int WindowSeconds { get; set; } = 60;
    
    /// <summary>
    /// Default cost limit per window for authenticated users.
    /// </summary>
    public long DefaultMaxCost { get; set; } = 1000;
    
    /// <summary>
    /// Cost limit for anonymous users (typically lower).
    /// </summary>
    public long AnonymousMaxCost { get; set; } = 100;
    
    /// <summary>
    /// Cost multipliers per role. Higher roles get more budget.
    /// </summary>
    public Dictionary<string, double> RoleMultipliers { get; set; } = new()
    {
        { "Admin", 10.0 },
        { "User", 2.0 },
        { "Viewer", 1.0 }
    };
    
    /// <summary>
    /// Base cost per field accessed.
    /// </summary>
    public int CostPerField { get; set; } = 1;
    
    /// <summary>
    /// Additional cost per depth level.
    /// </summary>
    public int CostPerDepthLevel { get; set; } = 2;
    
    /// <summary>
    /// Cost multiplier for mutations (typically higher than queries).
    /// </summary>
    public double MutationMultiplier { get; set; } = 5.0;
    
    /// <summary>
    /// Cost multiplier for list fields (pagination).
    /// </summary>
    public double ListFieldMultiplier { get; set; } = 10.0;
    
    /// <summary>
    /// Maximum allowed depth for queries.
    /// </summary>
    public int MaxDepth { get; set; } = 10;
    
    /// <summary>
    /// Maximum number of fields per query.
    /// </summary>
    public int MaxFields { get; set; } = 100;
    
    /// <summary>
    /// Number of recent requests to keep in history per user.
    /// </summary>
    public int MaxHistoryEntries { get; set; } = 50;
}

/// <summary>
/// Result of a cost calculation.
/// </summary>
public class CostCalculationResult
{
    public long TotalCost { get; set; }
    public int FieldCount { get; set; }
    public int MaxDepth { get; set; }
    public bool IsMutation { get; set; }
    public List<string> FieldsAccessed { get; set; } = new();
    public List<string> Warnings { get; set; } = new();
    
    /// <summary>
    /// Whether the query exceeds complexity limits.
    /// </summary>
    public bool ExceedsLimits { get; set; }
    
    /// <summary>
    /// Reason if the query exceeds limits.
    /// </summary>
    public string? LimitExceededReason { get; set; }
}
