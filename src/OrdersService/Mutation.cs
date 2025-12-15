using OrdersService.Commands;
using OrdersService.Models;
using Wolverine;

namespace OrdersService;

public class Mutation
{
    /// <summary>
    /// Places a new order for a specific product.
    /// This initiates the order processing workflow, including inventory checks and shipping allocation.
    /// </summary>
    /// <param name="bus">The message bus for command dispatch.</param>
    /// <param name="productId">The unique identifier of the product to order.</param>
    /// <param name="quantity">The number of units to order.</param>
    /// <returns>The newly created order with its initial status.</returns>
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
