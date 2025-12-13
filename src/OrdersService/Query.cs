using OrdersService.Data;
using OrdersService.Models;

namespace OrdersService;

public class Query
{
    [UsePaging]
    [UseFiltering]
    [UseSorting]
    public IEnumerable<Order> GetOrders([Service] OrderRepository repository)
    {
        return repository.GetAll();
    }
}
