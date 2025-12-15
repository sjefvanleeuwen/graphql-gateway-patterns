using Shouldly;
using ShippingService;
using Xunit;

namespace ShippingService.Tests;

public class QueryTests
{
    [Fact]
    public void GetShipping_ShouldReturnOptionsForProduct()
    {
        // Arrange
        var query = new Query();
        var productId = "123";

        // Act
        var result = query.GetShipping(productId);

        // Assert
        result.ShouldNotBeNull();
        result.Count().ShouldBe(3);
        result.ShouldContain(x => x.Carrier == "Standard");
        result.ShouldContain(x => x.Carrier == "Express");
        result.ShouldContain(x => x.Carrier == "Overnight");
    }

    [Fact]
    public void GetShipping_ShouldBeDeterministic()
    {
        // Arrange
        var query = new Query();
        var productId = "123";

        // Act
        var result1 = query.GetShipping(productId);
        var result2 = query.GetShipping(productId);

        // Assert
        result1.First().Cost.ShouldBe(result2.First().Cost);
    }
}
