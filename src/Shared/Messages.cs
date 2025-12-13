using System;

namespace Shared
{
    public record OrderPlaced(string OrderId, string ProductId, int Quantity);
    public record OrderProcessed(string OrderId, DateTime ProcessedAt);
}
