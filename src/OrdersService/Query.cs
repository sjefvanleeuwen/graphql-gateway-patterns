using OrdersService.Data;
using OrdersService.Models;

namespace OrdersService;

public class Query
{
    /// <summary>
    /// Retrieves a paginated, filterable, and sortable list of all orders in the system.
    /// Use this query to browse order history or find specific orders by ID, status, or date.
    /// </summary>
    [UsePaging]
    [UseFiltering]
    [UseSorting]
    public IEnumerable<Order> GetOrders([Service] OrderRepository repository)
    {
        return repository.GetAll();
    }
}
