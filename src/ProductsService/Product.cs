using HotChocolate.Types;

namespace ProductsService;

public record Product([property: ID] string Id, string Name, double Price, string Description);
