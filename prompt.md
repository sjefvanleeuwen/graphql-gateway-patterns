Create a complete .NET solution demonstrating a Hot Chocolate GraphQL Gateway using Fusion.

The goal is to show how to aggregate one existing GraphQL service and two existing RESTful services into a single unified Graph.

### Domain Scenario: E-Commerce
We want to fetch a Product and see its details, user reviews, and shipping estimates in a single query.

### Components

1.  **Products Service (GraphQL)**
    *   Technology: Hot Chocolate (ASP.NET Core).
    *   Responsibility: Manages product core data.
    *   Types: `Product` (Id, Name, Price, Description).
    *   Query: `product(id: ID): Product`

2.  **Reviews Service (REST)**
    *   Technology: ASP.NET Core Web API (Minimal API or Controllers).
    *   Responsibility: Manages customer reviews.
    *   Endpoints:
        *   `GET /reviews/{productId}`: Returns a list of reviews for a specific product.
    *   *Note*: This service needs to be integrated into the gateway so that the `Product` type in the Gateway has a `reviews` field.

3.  **Shipping Service (REST)**
    *   Technology: ASP.NET Core Web API.
    *   Responsibility: Calculates shipping costs.
    *   Endpoints:
        *   `GET /shipping/{productId}`: Returns shipping options/estimates for a product.
    *   *Note*: This service needs to be integrated so that the `Product` type has a `shipping` field.

4.  **Gateway (Hot Chocolate Fusion)**
    *   Technology: Hot Chocolate Fusion.
    *   Responsibility: Aggregates the Subgraph (Products) and the two REST services (Reviews, Shipping).
    *   It must resolve the relationships so I can query:
        ```graphql
        query {
          product(id: "1") {
            name
            price
            reviews {
              content
              starRating
            }
            shipping {
              carrier
              cost
              estimatedDays
            }
          }
        }
        ```

### Deliverables
*   Project structure for the 4 projects.
*   Code for the GraphQL Service.
*   Code for the 2 REST Services (including Swagger/OpenAPI generation, which is needed for Fusion).
*   **Crucial**: The setup steps or script to compose the Fusion configuration (`gateway.fgp`). This usually involves:
    1.  Exporting the GraphQL Schema.
    2.  Exporting the Swagger/OpenAPI JSON for the REST services.
    3.  Using the `dotnet fusion` CLI to compose them into a single package.
*   The Gateway startup code.
*   Instructions on how to run and test.
