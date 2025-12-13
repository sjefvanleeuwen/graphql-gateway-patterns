using System;
using System.Threading.Tasks;
using Shared;
using Wolverine;

namespace BackOfficeService
{
    public class OrderHandler
    {
        public async Task Handle(OrderPlaced message, IMessageContext context)
        {
            Console.WriteLine($"[BackOffice] Received OrderPlaced: {message.OrderId}. Processing...");
            
            // Simulate async processing
            await Task.Delay(5000);
            
            Console.WriteLine($"[BackOffice] Order {message.OrderId} processed. Sending OrderProcessed event.");
            
            await context.PublishAsync(new OrderProcessed(message.OrderId, DateTime.UtcNow));
        }
    }
}
