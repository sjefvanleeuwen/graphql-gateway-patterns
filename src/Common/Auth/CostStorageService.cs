using System.Collections.Concurrent;
using System.Security.Claims;

namespace Common.Auth;

/// <summary>
/// Interface for storing and retrieving user cost statistics.
/// </summary>
public interface ICostStorageService
{
    /// <summary>
    /// Gets the cost statistics for a user.
    /// </summary>
    UserCostStatistics GetUserStatistics(string userId);
    
    /// <summary>
    /// Records a cost entry for a user.
    /// </summary>
    void RecordCost(string userId, CostEntry entry, CostLimitConfig config);
    
    /// <summary>
    /// Checks if a user can afford the given cost.
    /// </summary>
    bool CanAffordCost(string userId, long cost);
    
    /// <summary>
    /// Gets all users with their statistics (for admin monitoring).
    /// </summary>
    IEnumerable<UserCostStatistics> GetAllStatistics();
    
    /// <summary>
    /// Clears statistics for a specific user.
    /// </summary>
    void ClearUserStatistics(string userId);
    
    /// <summary>
    /// Clears all statistics (admin operation).
    /// </summary>
    void ClearAllStatistics();
}

/// <summary>
/// In-memory implementation of cost storage.
/// Thread-safe for concurrent access.
/// </summary>
public class InMemoryCostStorageService : ICostStorageService
{
    private readonly ConcurrentDictionary<string, UserCostStatistics> _userStats = new();
    private readonly CostLimitConfig _defaultConfig;

    public InMemoryCostStorageService(CostLimitConfig? defaultConfig = null)
    {
        _defaultConfig = defaultConfig ?? new CostLimitConfig();
    }

    public UserCostStatistics GetUserStatistics(string userId)
    {
        return _userStats.GetOrAdd(userId, id => CreateNewStatistics(id, _defaultConfig));
    }

    public void RecordCost(string userId, CostEntry entry, CostLimitConfig config)
    {
        var stats = _userStats.GetOrAdd(userId, id => CreateNewStatistics(id, config));
        
        lock (stats)
        {
            // Check if window has expired
            if (DateTime.UtcNow >= stats.WindowEnd)
            {
                // Reset window
                stats.TotalCost = 0;
                stats.RequestCount = 0;
                stats.WindowStart = DateTime.UtcNow;
                stats.WindowEnd = DateTime.UtcNow.AddSeconds(config.WindowSeconds);
                stats.RecentRequests.Clear();
            }
            
            // Record the cost
            stats.TotalCost += entry.CalculatedCost;
            stats.RequestCount++;
            stats.RecentRequests.Add(entry);
            
            // Trim history if needed
            while (stats.RecentRequests.Count > config.MaxHistoryEntries)
            {
                stats.RecentRequests.RemoveAt(0);
            }
        }
    }

    public bool CanAffordCost(string userId, long cost)
    {
        var stats = GetUserStatistics(userId);
        
        lock (stats)
        {
            // Check if window has expired (would reset)
            if (DateTime.UtcNow >= stats.WindowEnd)
            {
                return true; // New window, full budget available
            }
            
            return stats.RemainingCost >= cost;
        }
    }

    public IEnumerable<UserCostStatistics> GetAllStatistics()
    {
        return _userStats.Values.ToList();
    }

    public void ClearUserStatistics(string userId)
    {
        _userStats.TryRemove(userId, out _);
    }

    public void ClearAllStatistics()
    {
        _userStats.Clear();
    }

    private UserCostStatistics CreateNewStatistics(string userId, CostLimitConfig config)
    {
        return new UserCostStatistics
        {
            UserId = userId,
            WindowStart = DateTime.UtcNow,
            WindowEnd = DateTime.UtcNow.AddSeconds(config.WindowSeconds),
            MaxCostPerWindow = config.DefaultMaxCost
        };
    }
}

/// <summary>
/// Extension methods for cost storage.
/// </summary>
public static class CostStorageExtensions
{
    /// <summary>
    /// Extracts the user ID from ClaimsPrincipal for cost tracking.
    /// Falls back to "anonymous" if not authenticated.
    /// </summary>
    public static string GetCostTrackingUserId(this ClaimsPrincipal user)
    {
        if (user.Identity?.IsAuthenticated != true)
        {
            return "anonymous";
        }
        
        // Try common claim types for user ID
        var userId = user.FindFirst(ClaimTypes.NameIdentifier)?.Value
            ?? user.FindFirst("sub")?.Value
            ?? user.FindFirst(ClaimTypes.Name)?.Value
            ?? user.Identity.Name
            ?? "unknown";
            
        return userId;
    }
    
    /// <summary>
    /// Gets the maximum cost budget for a user based on their roles.
    /// </summary>
    public static long GetMaxCostForUser(this ClaimsPrincipal user, CostLimitConfig config)
    {
        if (user.Identity?.IsAuthenticated != true)
        {
            return config.AnonymousMaxCost;
        }
        
        // Find the highest multiplier from user's roles
        double highestMultiplier = 1.0;
        
        foreach (var (role, multiplier) in config.RoleMultipliers)
        {
            if (user.IsInRole(role) && multiplier > highestMultiplier)
            {
                highestMultiplier = multiplier;
            }
        }
        
        return (long)(config.DefaultMaxCost * highestMultiplier);
    }
}
