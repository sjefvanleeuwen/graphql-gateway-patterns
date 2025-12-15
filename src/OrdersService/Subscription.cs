using HotChocolate;
using HotChocolate.Types;
using OrdersService.Models;

namespace OrdersService;

public class Subscription
{
    /// <summary>
    /// Subscribes to real-time updates for any order in the system.
    /// You will receive an event whenever an order's status changes (e.g., from 'Placed' to 'Shipped').
    /// </summary>
    /// <param name="order">The order object received from the event.</param>
    /// <returns>The updated order details.</returns>
    [Subscribe]
    [Topic("OrderUpdated")]
    public Order OnOrderUpdated([EventMessage] Order order) => order;
}
