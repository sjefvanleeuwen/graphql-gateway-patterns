using Shouldly;
using OrdersService;
using OrdersService.Data;
using OrdersService.Models;
using Xunit;

namespace OrdersService.Tests;

public class QueryTests
{
    [Fact]
    public void GetOrders_ShouldReturnOrdersFromRepository()
    {
        // Arrange
        var repository = new OrderRepository();
        repository.Add(new Order("1", "prod1", 1, 10.0, "Pending"));
        var query = new Query();

        // Act
        var result = query.GetOrders(repository);

        // Assert
        result.Count().ShouldBe(1);
        result.First().Id.ShouldBe("1");
    }
}
