using HotChocolate.Authorization;
using HotChocolate.Types;

namespace ProductsService;

/// <summary>
/// GraphQL type configuration for Product with field-level authorization.
/// Demonstrates RBAC at the field level - price is only visible to Admin/User.
/// </summary>
public class ProductType : ObjectType<Product>
{
    protected override void Configure(IObjectTypeDescriptor<Product> descriptor)
    {
        descriptor.Description("A product in the catalog.");

        descriptor.Field(p => p.Id)
            .Description("Unique identifier for the product.");

        descriptor.Field(p => p.Name)
            .Description("Product name - visible to everyone.");

        descriptor.Field(p => p.Description)
            .Description("Product description - visible to everyone.");

        // Field-level RBAC: Price requires CanViewPrices policy (Admin or User)
        // Viewers will get an authorization error when trying to access this field
        descriptor.Field(p => p.Price)
            .Description("Product price - only visible to Admin and User roles.")
            .Authorize(policy: "CanViewPrices");
    }
}
