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

    public Product? GetProduct(string id)
    {
        return _products.FirstOrDefault(p => p.Id == id);
    }

    [UsePaging]
    [UseFiltering]
    [UseSorting]
    public IEnumerable<Product> GetProducts()
    {
        return _products;
    }
}
