namespace ProductsService;

public class ProductPage
{
    public IEnumerable<Product> Nodes { get; set; } = new List<Product>();
    public int TotalCount { get; set; }
}
