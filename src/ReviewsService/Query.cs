using HotChocolate.Types;

namespace ReviewsService;

public class Query
{
    private readonly List<Review> _reviews;

    public Query()
    {
        _reviews = new List<Review>
        {
            new Review("1", "1", "Love it!", 5),
            new Review("2", "1", "It's okay.", 3),
            new Review("3", "2", "Could be better.", 2),
            new Review("4", "2", "Great value.", 4),
            new Review("5", "3", "Not what I expected.", 1)
        };
    }

    /// <summary>
    /// Retrieves a list of customer reviews.
    /// Can be filtered by product ID to show reviews for a specific item.
    /// </summary>
    /// <returns>A collection of reviews.</returns>
    [UsePaging]
    [UseFiltering]
    [UseSorting]
    public IEnumerable<Review> GetReviews() => _reviews;

    /// <summary>
    /// Retrieves a specific review by its ID.
    /// </summary>
    /// <param name="id">The unique identifier of the review.</param>
    /// <returns>The review details.</returns>
    public Review? GetReview(string id) => _reviews.FirstOrDefault(r => r.Id == id);
}
