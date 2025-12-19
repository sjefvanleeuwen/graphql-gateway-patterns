using OrdersService.Data;
using OrdersService.Models;

namespace OrdersService;

public class Query
{
    /// <summary>
    /// Get all orders.
    /// Authorization is handled at the Gateway level (CanViewOrders policy).
    /// </summary>
    [UsePaging]
    [UseFiltering]
    [UseSorting]
    public IEnumerable<Order> GetOrders([Service] OrderRepository repository)
    {
        return repository.GetAll();
    }
}
