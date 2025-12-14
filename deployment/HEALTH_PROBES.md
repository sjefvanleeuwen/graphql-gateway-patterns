# Health Probes Configuration

## Overview
Health probes are now configured for all services to automatically detect and restart containers that become unhealthy.

## Probe Types

### Liveness Probe (HTTP GET)
- **Purpose**: Detects if container is running or has crashed/hung
- **Frequency**: Every 10 seconds
- **Timeout**: 5 seconds
- **Action**: Restarts container if probe fails
- **Services**: All GraphQL services + Frontend

### Endpoints Probed

#### GraphQL Services (Products, Reviews, Shipping, Orders, BackOffice, Gateway)
- **Endpoint**: `http://<service>:8080/graphql`
- **Method**: GET
- **Success Criteria**: HTTP 200 response (GraphQL endpoint responds)
- **Detects**: 
  - Service crashes
  - Database connection failures (Orders, BackOffice)
  - Async messaging issues (BackOffice with Wolverine)
  - Fusion gateway composition issues

#### Frontend
- **Endpoint**: `http://frontend:80/`
- **Method**: GET
- **Success Criteria**: HTTP 200 response (Nginx serving files)
- **Detects**:
  - Nginx process crashes
  - Static file serving issues

## What Probes Can Detect

### ✅ Detected Issues
1. **Container Crashes**: Process termination, OutOfMemory, segfaults
2. **Application Hangs**: Service not responding to requests
3. **Database Connectivity**: Postgres connection failures in Orders/BackOffice
4. **Wolverine Messaging Issues**: Message processing failures in BackOffice
5. **GraphQL Schema Issues**: Malformed schemas preventing initialization
6. **SignalR Subscription Issues**: Indirectly - if Orders can't initialize subscriptions, the `/graphql` endpoint fails
7. **Configuration Errors**: Missing env vars, invalid connection strings

### ❌ Not Directly Detected (Need Application Health Endpoints)
- Message queue backup/delay
- Database query performance issues
- Memory leaks (until OOM)
- Slow Wolverine message processing
- GraphQL subscription latency

## Improvement: Custom Health Endpoints

For more granular monitoring, we could add custom health check endpoints to the services that report:

```csharp
// Example health endpoint for Orders/BackOffice
builder.MapHealthChecks("/health", new HealthCheckOptions
{
    ResponseWriter = WriteHealthCheckResponse
});

services.AddHealthChecks()
    .AddDbContextCheck<OrdersDbContext>()  // Check Postgres connectivity
    .AddCheck("wolverine", new WolverineHealthCheck());  // Check messaging
```

This would allow probes to detect:
- Postgres connectivity status
- Wolverine agent health
- Message queue backlog
- Subscription system status

## Current Probe Configuration

```yaml
All Services:
  Type: HTTP (GET)
  Interval: 10 seconds
  Timeout: 5 seconds
  Failure Threshold: Not specified (defaults to 3 failures)
  
GraphQL Services:
  Path: /graphql
  Port: 8080
  
Frontend:
  Path: /
  Port: 80
```

## Monitoring Health in Azure Portal

1. **Container Apps** → Select service → **Revisions** → **Monitoring** → **Container** → View probe metrics
2. **Log Analytics** → Query `ContainerAppConsoleLogs_CL` for health check logs
3. **Application Insights** → Check availability tests if configured

## Next Steps

To further improve observability:

1. **Add custom `/health` endpoints** to Orders and BackOffice services
2. **Add health checks for**:
   - Postgres database connectivity
   - Wolverine agent status
   - Message queue health
   - GraphQL subscription system
3. **Configure alerts** in Azure Monitor when probes fail
4. **Set minimum replicas** to 2+ for critical services (Orders, BackOffice) to ensure fault tolerance
