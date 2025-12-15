using Shouldly;
using ProductsService;
using Xunit;

namespace ProductsService.Tests;

public class QueryTests
{
    [Fact]
    public void GetProducts_ShouldReturnAllProducts()
    {
        // Arrange
        var query = new Query();

        // Act
        var result = query.GetProducts();

        // Assert
        result.ShouldNotBeNull();
        result.Count().ShouldBe(50);
        result.First().Name.ShouldBe("Product 1");
    }

    [Fact]
    public void GetProduct_WithValidId_ShouldReturnProduct()
    {
        // Arrange
        var query = new Query();

        // Act
        var result = query.GetProduct("1");

        // Assert
        result.ShouldNotBeNull();
        result!.Id.ShouldBe("1");
        result.Name.ShouldBe("Product 1");
    }

    [Fact]
    public void GetProduct_WithInvalidId_ShouldReturnNull()
    {
        // Arrange
        var query = new Query();

        // Act
        var result = query.GetProduct("999");

        // Assert
        result.ShouldBeNull();
    }
}
