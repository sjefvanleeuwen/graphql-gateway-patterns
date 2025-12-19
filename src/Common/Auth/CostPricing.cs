namespace Common.Auth;

/// <summary>
/// Configuration for converting query costs to currency (euros).
/// </summary>
public class CostPricingConfig
{
    /// <summary>
    /// Base multiplier to convert complexity cost to euros.
    /// Default: 0.001 (1 cost unit = €0.001)
    /// </summary>
    public double CostToEuroMultiplier { get; set; } = 0.001;
    
    /// <summary>
    /// Pricing per account tier.
    /// </summary>
    public Dictionary<string, TierPricing> TierPricing { get; set; } = new();
}

/// <summary>
/// Pricing configuration for a specific account tier.
/// </summary>
public class TierPricing
{
    /// <summary>
    /// Monthly subscription fee for this tier.
    /// </summary>
    public double MonthlyFee { get; set; }
    
    /// <summary>
    /// Cost multiplier for this tier (euros per cost unit).
    /// Lower tiers pay more per query complexity.
    /// </summary>
    public double CostMultiplier { get; set; }
}

/// <summary>
/// User cost statistics with euro pricing.
/// </summary>
public class UserCostWithPricing
{
    public string UserId { get; set; } = string.Empty;
    public string? UserName { get; set; }
    public string AccountTier { get; set; } = "Normal";
    
    // Current window stats
    public DateTime WindowStart { get; set; }
    public DateTime WindowEnd { get; set; }
    public long TotalCost { get; set; }
    public long MaxCostPerWindow { get; set; }
    public long RemainingCost { get; set; }
    public int RequestCount { get; set; }
    public bool IsOverBudget { get; set; }
    
    // Pricing information
    public double CostInEuros { get; set; }
    public double MonthlyFee { get; set; }
    public double CostMultiplier { get; set; }
    
    // Historical data
    public List<DailyCostSummary> DailyCosts { get; set; } = new();
    public List<CostEntryWithPrice> RecentRequests { get; set; } = new();
}

/// <summary>
/// Daily cost summary with pricing.
/// </summary>
public class DailyCostSummary
{
    public DateTime Date { get; set; }
    public long TotalCost { get; set; }
    public int RequestCount { get; set; }
    public double CostInEuros { get; set; }
}

/// <summary>
/// Cost entry with euro pricing.
/// </summary>
public class CostEntryWithPrice
{
    public DateTime Timestamp { get; set; }
    public string? OperationName { get; set; }
    public int FieldCount { get; set; }
    public int Depth { get; set; }
    public long CalculatedCost { get; set; }
    public double CostInEuros { get; set; }
    public bool WasAllowed { get; set; }
}
