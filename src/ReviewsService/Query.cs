namespace ReviewsService;

public class Query
{
    private readonly List<Review> _reviews;

    public Query()
    {
        _reviews = new List<Review>();
        var random = new Random(42); // Seed for consistency

        for (int i = 1; i <= 50; i++)
        {
            var reviewCount = random.Next(1, 6);
            for (int j = 0; j < reviewCount; j++)
            {
                _reviews.Add(new Review(
                    $"{i}-{j}", 
                    i.ToString(), 
                    $"Review {j + 1} for Product {i}. This is some sample content.", 
                    random.Next(1, 6)
                ));
            }
        }
    }

    [UsePaging]
    [UseFiltering]
    [UseSorting]
    public IEnumerable<Review> GetReviews() => _reviews;
    
    public Review? GetReview(string id) => _reviews.FirstOrDefault(r => r.Id == id);
}
