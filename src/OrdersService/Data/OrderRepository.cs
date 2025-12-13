using OrdersService.Models;

namespace OrdersService.Data;

public class OrderRepository
{
    private readonly List<Order> _orders = new();

    public void Add(Order order)
    {
        _orders.Add(order);
    }

    public IEnumerable<Order> GetAll()
    {
        return _orders;
    }

    public Order? GetById(string id)
    {
        return _orders.FirstOrDefault(o => o.Id == id);
    }

    public void Update(Order order)
    {
        var existing = _orders.FirstOrDefault(o => o.Id == order.Id);
        if (existing != null)
        {
            _orders.Remove(existing);
            _orders.Add(order);
        }
    }
}
