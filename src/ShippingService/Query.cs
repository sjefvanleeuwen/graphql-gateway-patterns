namespace ShippingService;

public class Query
{
    [UsePaging]
    [UseFiltering]
    [UseSorting]
    public IEnumerable<ShippingOption> GetShipping(string productId)
    {
        // Generate deterministic shipping options based on productId
        var seed = productId.GetHashCode();
        var random = new Random(seed);
        
        return new List<ShippingOption>
        {
            new("Standard", Math.Round(5.0 + random.NextDouble() * 10, 2), random.Next(3, 8)),
            new("Express", Math.Round(15.0 + random.NextDouble() * 15, 2), random.Next(1, 3)),
            new("Overnight", Math.Round(30.0 + random.NextDouble() * 20, 2), 1)
        };
    }
}
