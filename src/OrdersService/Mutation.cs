using OrdersService.Commands;
using OrdersService.Models;
using Wolverine;

namespace OrdersService;

public class Mutation
{
    /// <summary>
    /// Place a new order.
    /// Authorization is handled at the Gateway level (CanPlaceOrders policy).
    /// </summary>
    public async Task<Order> PlaceOrder(
        [Service] IMessageBus bus,
        string productId,
        int quantity)
    {
        var command = new PlaceOrder(productId, quantity);
        // InvokeAsync sends the command to the bus and waits for the handler to return the result
        return await bus.InvokeAsync<Order>(command);
    }
}
