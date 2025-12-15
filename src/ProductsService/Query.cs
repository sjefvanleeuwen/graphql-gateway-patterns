using HotChocolate.Types.Relay;

namespace ProductsService;

public class Query
{
    private readonly List<Product> _products;

    public Query()
    {
        _products = Enumerable.Range(1, 50).Select(i => 
            new Product(
                i.ToString(), 
                $"Product {i}", 
                Math.Round(10.0 + (i * 1.5), 2), 
                $"Description for product {i}"
            )).ToList();
    }

    /// <summary>
    /// Retrieves a single product by its unique identifier.
    /// </summary>
    /// <param name="id">The ID of the product.</param>
    /// <returns>The product if found, otherwise null.</returns>
    [NodeResolver]
    public Product? GetProduct(string id)
    {
        return _products.FirstOrDefault(p => p.Id == id);
    }

    /// <summary>
    /// Retrieves a catalog of available products.
    /// Supports pagination, filtering, and sorting to help users find specific items.
    /// </summary>
    /// <returns>A list of products.</returns>
    [UsePaging]
    [UseFiltering]
    [UseSorting]
    public IEnumerable<Product> GetProducts()
    {
        return _products;
    }
}
