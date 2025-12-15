using Shouldly;
using Moq;
using OrdersService;
using OrdersService.Commands;
using OrdersService.Models;
using Wolverine;
using Xunit;

namespace OrdersService.Tests;

public class MutationTests
{
    [Fact]
    public async Task PlaceOrder_ShouldInvokeBusAndReturnOrder()
    {
        // Arrange
        var busMock = new Mock<IMessageBus>();
        var expectedOrder = new Order("1", "prod1", 2, 100.0, "Pending");
        
        busMock.Setup(x => x.InvokeAsync<Order>(It.IsAny<PlaceOrder>(), It.IsAny<CancellationToken>(), It.IsAny<TimeSpan?>()))
            .ReturnsAsync(expectedOrder);

        var mutation = new Mutation();

        // Act
        var result = await mutation.PlaceOrder(busMock.Object, "prod1", 2);

        // Assert
        result.ShouldBe(expectedOrder);
        busMock.Verify(x => x.InvokeAsync<Order>(
            It.Is<PlaceOrder>(c => c.ProductId == "prod1" && c.Quantity == 2), 
            It.IsAny<CancellationToken>(), 
            It.IsAny<TimeSpan?>()), Times.Once);
    }
}
