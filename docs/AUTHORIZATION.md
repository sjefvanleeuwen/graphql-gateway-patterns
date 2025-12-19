# GraphQL Gateway Authorization Patterns

This document describes the authorization strategies for securing a GraphQL Fusion Gateway using JWT authentication and configuration-driven RBAC with **hot-reload** support.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Hot-Reload](#hot-reload)
- [Authorization Levels](#authorization-levels)
- [Configuration Reference](#configuration-reference)
- [Schema Directives](#schema-directives)
- [When to Use What](#when-to-use-what)
- [Examples](#examples)

---

## Overview

This implementation uses a **configuration-driven** approach where:

1. **JWT Authentication** - Validates tokens at the Gateway
2. **Policies in appsettings.json** - No code changes needed to modify access rules
3. **Schema Directives** - `@authorize` in GraphQL schemas reference policy names
4. **Hot-Reload** - Policies reload automatically when config changes, with WebSocket notifications

```
┌─────────────────────────────────────────────────────────────┐
│                        Client                                │
│                   (JWT Token in Header)                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Fusion Gateway                            │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  1. JWT Validation (Authentication)                  │    │
│  │  2. Policy Lookup (from appsettings.json)            │    │
│  │  3. @authorize directive enforcement                 │    │
│  │  4. Hot-reload on config change + WebSocket notify   │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                              │
          ┌───────────────────┼───────────────────┐
          ▼                   ▼                   ▼
    ┌──────────┐        ┌──────────┐        ┌──────────┐
    │ Products │        │  Orders  │        │ Reviews  │
    │ Subgraph │        │ Subgraph │        │ Subgraph │
    └──────────┘        └──────────┘        └──────────┘
```

---

## Architecture

### Two-Layer Authorization

**Layer 1: Configuration (appsettings.json)**
- Define reusable policies with roles and claims
- Change without recompiling
- Environment-specific (Dev/Staging/Prod can have different policies)
- **Hot-reload** - changes picked up automatically

**Layer 2: Schema Directives**
- `@authorize` directives in GraphQL schemas
- Reference policies by name
- Applied at operation, type, or field level
- Exported from subgraph code → composed into gateway

### Flow

```
1. Subgraph defines [Authorize(Policy = "CanPlaceOrders")] in C#
                    │
                    ▼
2. Schema export generates @authorize(policy: "CanPlaceOrders")
                    │
                    ▼
3. Fusion compose includes directive in gateway.fgp
                    │
                    ▼
4. Gateway looks up "CanPlaceOrders" in appsettings.json
                    │
                    ▼
5. Gateway enforces: Does user have Admin OR User role?
```

### Key Principle: Separation of Concerns

| What | Where | Can Change Without Recompile |
|------|-------|------------------------------|
| **What is protected** | Schema directives (`@authorize`) | No (requires schema re-export) |
| **Who can access** | appsettings.json policies | ✅ Yes (hot-reload) |
| **How to authenticate** | JWT validation in Gateway | No |

---

## Hot-Reload

Authorization policies support **hot-reload** - edit `appsettings.json` and changes take effect immediately without restart.

### How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                   appsettings.json                           │
│                  (file modified)                             │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              AuthorizationReloadService                      │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  1. FileSystemWatcher detects change                 │    │
│  │  2. IOptionsMonitor<AuthorizationConfig> updates     │    │
│  │  3. ConfigurationPolicyProvider uses new values      │    │
│  │  4. WebSocket notification sent                      │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              Subscribed Clients (WebSocket)                  │
│              Receive: onAuthorizationReloaded               │
└─────────────────────────────────────────────────────────────┘
```

### Subscribe to Authorization Changes

```graphql
subscription {
  onAuthorizationReloaded {
    reloadedAt
    policyCount
    policyNames
    trigger
  }
}
```

**Response when config changes:**
```json
{
  "data": {
    "onAuthorizationReloaded": {
      "reloadedAt": "2025-12-19T10:30:00Z",
      "policyCount": 7,
      "policyNames": ["AdminOnly", "CanViewPrices", "CanPlaceOrders", ...],
      "trigger": "File change detected: appsettings.json"
    }
  }
}
```

### Live Policy Update Example

1. **Current policy** (appsettings.json):
```json
"CanViewOrders": {
  "Roles": ["Admin", "User"]
}
```

2. **Edit and save** - add Marketing role:
```json
"CanViewOrders": {
  "Roles": ["Admin", "User", "Marketing"]
}
```

3. **Immediately effective** - Marketing users can now view orders
4. **WebSocket notification** - subscribed clients notified

### Components

| Component | Purpose |
|-----------|---------|
| `ConfigurationPolicyProvider` | Dynamic policy provider using `IOptionsMonitor` |
| `AuthorizationReloadService` | Watches config files, sends WebSocket notifications |
| `onAuthorizationReloaded` | GraphQL subscription for clients |

---

## Authorization Levels

### Level 1: Operation Level
Protect entire queries or mutations.

```graphql
type Mutation {
  placeOrder(productId: String!, quantity: Int!): Order! 
    @authorize(policy: "CanPlaceOrders")
}
```

**Use when:** Entire operations should be restricted.

### Level 2: Type/Entity Level
Protect all fields of a type.

```graphql
type Order @authorize(policy: "CanViewOrders") {
  id: String!
  productId: String!
  totalPrice: Float!
}
```

**Use when:** All fields of a type share the same access rules.

### Level 3: Field Level
Protect individual sensitive fields.

```graphql
type Product {
  id: ID!
  name: String!
  description: String!
  price: Float! @authorize(policy: "CanViewPrices")
  internalCost: Float! @authorize(policy: "AdminOnly")
}
```

**Use when:** Different fields have different sensitivity levels.

### Level 4: Row/Data Level
Filter data based on user context. This requires code in resolvers.

```csharp
[Authorize]
public IEnumerable<Order> GetMyOrders(ClaimsPrincipal user)
{
    var userId = user.FindFirst(ClaimTypes.NameIdentifier)?.Value;
    return user.IsInRole("Admin") 
        ? repo.GetAll() 
        : repo.GetByUserId(userId);
}
```

**Use when:** Data visibility depends on who's asking.

---

## Configuration Reference

### appsettings.json Structure

```json
{
  "JwtSettings": {
    "SecretKey": "YourSuperSecretKeyThatIsAtLeast32BytesLong!",
    "Issuer": "GraphQLGateway",
    "Audience": "GraphQLGatewayClients",
    "ExpirationMinutes": 60
  },
  "Authorization": {
    "Policies": {
      "PolicyName": {
        "RequireAuthentication": true,
        "Roles": ["Role1", "Role2"],
        "Claims": [
          {
            "Type": "claim-type",
            "Values": ["value1", "value2"]
          }
        ]
      }
    }
  }
}
```

### Policy Options

| Property | Type | Description |
|----------|------|-------------|
| `RequireAuthentication` | boolean | If true, any authenticated user passes |
| `Roles` | string[] | User must have at least one of these roles (OR logic) |
| `Claims` | array | Additional claim requirements |
| `Claims[].Type` | string | Claim type to check |
| `Claims[].Values` | string[] | Allowed values (OR logic). Empty = just check claim exists |

### Current Policies

```json
{
  "Authorization": {
    "Policies": {
      "AdminOnly": {
        "Roles": ["Admin"]
      },
      "AdminOrUser": {
        "Roles": ["Admin", "User"]
      },
      "Authenticated": {
        "RequireAuthentication": true
      },
      "CanViewPrices": {
        "Roles": ["Admin", "User"]
      },
      "CanViewOrders": {
        "Roles": ["Admin", "User"]
      },
      "CanPlaceOrders": {
        "Roles": ["Admin", "User"]
      },
      "CanViewReviews": {
        "RequireAuthentication": true
      },
      "PremiumUser": {
        "Roles": ["User"],
        "Claims": [
          {
            "Type": "subscription",
            "Values": ["premium", "enterprise"]
          }
        ]
      }
    }
  }
}
```

---

## Schema Directives

### Adding Authorization to Subgraphs (C#)

```csharp
// Operation level - protects the mutation
public class Mutation
{
    [Authorize(Policy = "CanPlaceOrders")]
    public async Task<Order> PlaceOrder(...) { }
}

// Type level - protects all fields
[Authorize(Policy = "CanViewOrders")]
public record Order(...);

// Field level - using ObjectType configuration
public class ProductType : ObjectType<Product>
{
    protected override void Configure(IObjectTypeDescriptor<Product> descriptor)
    {
        descriptor.Field(p => p.Price)
            .Authorize(policy: "CanViewPrices");
    }
}
```

### Exported Schema Result

After running schema export, the directives appear in `.graphql` files:

```graphql
type Mutation {
  placeOrder(productId: String!, quantity: Int!): Order! 
    @authorize(policy: "CanPlaceOrders")
}

type Order @authorize(policy: "CanViewOrders") {
  id: String!
  totalPrice: Float!
}

type Product {
  id: ID!
  name: String!
  price: Float! @authorize(policy: "CanViewPrices")
}
```

### Re-compose After Schema Changes

After adding `[Authorize]` attributes:

```powershell
cd src
.\compose.ps1
```

---

## When to Use What

### Quick Decision Guide

| Scenario | Approach |
|----------|----------|
| Simple role checks | Policy with `Roles` array |
| Any logged-in user | Policy with `RequireAuthentication: true` |
| Subscription tiers | Policy with `Claims` |
| Protect entire operation | `@authorize` on Query/Mutation field |
| Protect sensitive fields only | `@authorize` on specific fields |
| Different rules per environment | Override in `appsettings.{Environment}.json` |
| Data filtering by user | Code in resolver with `ClaimsPrincipal` |

### Decision Matrix

| What you want to change | Where to change | Recompile needed? |
|------------------------|-----------------|-------------------|
| Which roles can access a policy | appsettings.json | ❌ No |
| Add new policy | appsettings.json | ❌ No |
| Protect a new field/operation | Subgraph C# code + re-compose | ✅ Yes |
| Change policy name on a field | Subgraph C# code + re-compose | ✅ Yes |
| Environment-specific rules | appsettings.{Env}.json | ❌ No |

---

## Examples

### Example 1: Changing Access Without Recompiling

Scenario: Marketing team needs temporary access to orders.

**Before (appsettings.json):**
```json
"CanViewOrders": {
  "Roles": ["Admin", "User"]
}
```

**After (just edit config and restart):**
```json
"CanViewOrders": {
  "Roles": ["Admin", "User", "Marketing"]
}
```

No code changes. No re-composition. Just restart the Gateway.

### Example 2: Environment-Specific Policies

**appsettings.Development.json:**
```json
{
  "Authorization": {
    "Policies": {
      "AdminOnly": {
        "RequireAuthentication": true
      }
    }
  }
}
```

**appsettings.Production.json:**
```json
{
  "Authorization": {
    "Policies": {
      "AdminOnly": {
        "Roles": ["Admin"]
      }
    }
  }
}
```

Result: In dev, any authenticated user is "admin". In prod, only real Admins.

### Example 3: Premium Feature with Claims

```json
{
  "PremiumAnalytics": {
    "Roles": ["User", "Admin"],
    "Claims": [
      {
        "Type": "subscription",
        "Values": ["premium", "enterprise"]
      }
    ]
  }
}
```

User must have User/Admin role AND premium/enterprise subscription claim.

### Example 4: Adding Field-Level Protection

1. **Add attribute in subgraph code:**
```csharp
public class ProductType : ObjectType<Product>
{
    protected override void Configure(IObjectTypeDescriptor<Product> descriptor)
    {
        descriptor.Field(p => p.WholesaleCost)
            .Authorize(policy: "AdminOnly");
    }
}
```

2. **Re-export and compose:**
```powershell
.\compose.ps1
```

3. **Policy already exists in config** - no config change needed if using existing policy name.

---

## Testing

### Get Test Tokens

```http
GET http://localhost:5000/auth/test-tokens
```

### Login

```http
POST http://localhost:5000/auth/login
Content-Type: application/json

{
  "username": "admin",
  "password": "admin123"
}
```

Test users: `admin/admin123`, `user/user123`, `viewer/viewer123`

### GraphQL with Token

```http
POST http://localhost:5000/graphql
Authorization: Bearer <token>
Content-Type: application/json

{
  "query": "{ products { nodes { id name price } } }"
}
```

---

## Security Best Practices

1. **Environment variables for secrets** - Never commit `SecretKey`
2. **Short token expiration** - 15-60 minutes
3. **HTTPS only** - Never send tokens over HTTP
4. **Audit logging** - Log authorization failures
5. **Least privilege** - Start restrictive, open up as needed

---

## Files Reference

| File | Purpose |
|------|---------|
| [Gateway/appsettings.json](../src/Gateway/appsettings.json) | JWT settings and authorization policies |
| [Gateway/Auth/AuthorizationConfig.cs](../src/Gateway/Auth/AuthorizationConfig.cs) | Configuration loader |
| [Gateway/Auth/TokenService.cs](../src/Gateway/Auth/TokenService.cs) | JWT token generation |
| [Gateway/Auth/AuthEndpoints.cs](../src/Gateway/Auth/AuthEndpoints.cs) | Login/test endpoints |
| [compose.ps1](../src/compose.ps1) | Re-compose gateway after schema changes |
