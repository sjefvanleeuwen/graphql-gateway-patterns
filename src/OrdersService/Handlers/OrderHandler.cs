using OrdersService.Commands;
using OrdersService.Data;
using OrdersService.Models;
using Wolverine;
using Shared;
using System.Threading.Tasks;
using System;
using HotChocolate.Subscriptions;

namespace OrdersService.Handlers;

public class OrderHandler
{
    private readonly OrderRepository _repository;
    private readonly ITopicEventSender _sender;

    public OrderHandler(OrderRepository repository, ITopicEventSender sender)
    {
        _repository = repository;
        _sender = sender;
    }

    public async Task<Order> Handle(PlaceOrder command, IMessageContext context)
    {
        // Simulate some logic, maybe calculating price (mocked here)
        var pricePerUnit = 10.0; // This would come from ProductsService in a real app
        var totalPrice = command.Quantity * pricePerUnit;

        var order = new Order(
            Id: Guid.NewGuid().ToString(),
            ProductId: command.ProductId,
            Quantity: command.Quantity,
            TotalPrice: totalPrice,
            Status: "Placed"
        );

        _repository.Add(order);
        
        Console.WriteLine($"Order placed: {order.Id} for Product {order.ProductId}");
        
        await context.PublishAsync(new OrderPlaced(order.Id, order.ProductId, order.Quantity));

        return order;
    }

    public async Task Handle(OrderProcessed message)
    {
        var order = _repository.GetById(message.OrderId);
        if (order != null)
        {
            var updatedOrder = order with { Status = "Processed" };
            _repository.Update(updatedOrder);
            Console.WriteLine($"[OrdersService] Order {message.OrderId} status updated to Processed.");
            
            await _sender.SendAsync("OrderUpdated", updatedOrder);
        }
    }
}
