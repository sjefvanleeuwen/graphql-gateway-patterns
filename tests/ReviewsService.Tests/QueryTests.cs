using Shouldly;
using ReviewsService;
using Xunit;

namespace ReviewsService.Tests;

public class QueryTests
{
    [Fact]
    public void GetReviews_ShouldReturnAllReviews()
    {
        // Arrange
        var query = new Query();

        // Act
        var result = query.GetReviews();

        // Assert
        result.ShouldNotBeNull();
        result.Count().ShouldBe(5);
    }

    [Fact]
    public void GetReview_WithValidId_ShouldReturnReview()
    {
        // Arrange
        var query = new Query();

        // Act
        var result = query.GetReview("1");

        // Assert
        result.ShouldNotBeNull();
        result!.Id.ShouldBe("1");
        result.Content.ShouldBe("Love it!");
    }
}
