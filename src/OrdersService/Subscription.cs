using HotChocolate;
using HotChocolate.Types;
using OrdersService.Models;

namespace OrdersService;

public class Subscription
{
    [Subscribe]
    [Topic("OrderUpdated")]
    public Order OnOrderUpdated([EventMessage] Order order) => order;
}
