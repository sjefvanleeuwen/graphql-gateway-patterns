# Ensure we are in the src directory
Set-Location $PSScriptRoot

# Generate Products Schema
Write-Host "Generating Products Schema..."
dotnet run --project ProductsService -- schema export --output "$PSScriptRoot/schemas/products.graphql"

# Generate Reviews Schema
Write-Host "Generating Reviews Schema..."
dotnet run --project ReviewsService -- schema export --output "$PSScriptRoot/schemas/reviews.graphql"

# Generate Shipping Schema
Write-Host "Generating Shipping Schema..."
dotnet run --project ShippingService -- schema export --output "$PSScriptRoot/schemas/shipping.graphql"

# Generate Orders Schema
Write-Host "Generating Orders Schema..."
dotnet run --project OrdersService -- schema export --output "$PSScriptRoot/schemas/orders.graphql"

# Pack Products Subgraph
dotnet fusion subgraph pack -w . -s schemas/products.graphql -c schemas/products-config.json -p schemas/products.fsp

# Pack Reviews Subgraph
dotnet fusion subgraph pack -w . -s schemas/reviews.graphql -c schemas/reviews-config.json -p schemas/reviews.fsp

# Pack Shipping Subgraph
dotnet fusion subgraph pack -w . -s schemas/shipping.graphql -c schemas/shipping-config.json -p schemas/shipping.fsp

# Pack Orders Subgraph
dotnet fusion subgraph pack -w . -s schemas/orders.graphql -c schemas/orders-config.json -p schemas/orders.fsp

# Pack Status Subgraph
dotnet fusion subgraph pack -w . -s schemas/status.graphql -c schemas/status-config.json -p schemas/status.fsp

# Compose Gateway
dotnet fusion compose -p Gateway/gateway.fgp -s schemas/products.fsp -s schemas/reviews.fsp -s schemas/shipping.fsp -s schemas/orders.fsp -s schemas/status.fsp

Write-Host "Gateway configuration generated at Gateway/gateway.fgp"
