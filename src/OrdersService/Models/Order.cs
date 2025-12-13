namespace OrdersService.Models;

public record Order(string Id, string ProductId, int Quantity, double TotalPrice, string Status)
{
    public Product Product => new Product(ProductId);
}
