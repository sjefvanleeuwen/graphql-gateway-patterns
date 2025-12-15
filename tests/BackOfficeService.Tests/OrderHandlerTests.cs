using BackOfficeService;
using Moq;
using Shared;
using Wolverine;
using Xunit;

namespace BackOfficeService.Tests;

public class OrderHandlerTests
{
    [Fact]
    public async Task Handle_ShouldProcessOrderAndPublishEvent()
    {
        // Arrange
        var handler = new OrderHandler();
        var contextMock = new Mock<IMessageContext>();
        var message = new OrderPlaced("123", "prod1", 5);

        // Act
        await handler.Handle(message, contextMock.Object);

        // Assert
        contextMock.Verify(
            x => x.PublishAsync(It.Is<OrderProcessed>(e => e.OrderId == "123"), It.IsAny<DeliveryOptions?>()),
            Times.Once);
    }
}
