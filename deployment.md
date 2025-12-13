# Deployment Plan (No Aspire)

This document outlines the deployment strategy for the GraphQL Gateway application, using **Docker Compose** for local development and **Azure Bicep** for cloud deployment, replacing the previous .NET Aspire orchestration.

## 1. Local Development Strategy (Docker Compose)

We use `docker-compose` to orchestrate the services locally. This provides a consistent environment that mirrors the cloud setup (containers) without the overhead of the Aspire AppHost.

### Setup
1.  **Dockerfiles**: Created for each service in `src/<Service>/Dockerfile`.
2.  **Compose File**: Created at `src/docker-compose.yml`.

### Running Locally
To start the application locally:
```bash
cd src
docker-compose up --build
```

### Access Points
- **Frontend**: [http://localhost:4999](http://localhost:4999)
- **Gateway**: [http://localhost:5000/graphql](http://localhost:5000/graphql)
- **Products**: [http://localhost:5001/graphql](http://localhost:5001/graphql)
- **Reviews**: [http://localhost:5002/graphql](http://localhost:5002/graphql)
- **Shipping**: [http://localhost:5003/graphql](http://localhost:5003/graphql)
- **Orders**: [http://localhost:5004/graphql](http://localhost:5004/graphql)

### Configuration Notes
- **Gateway Configuration**: The `gateway.fgp` file is generated from `src/schemas/*-config.json`. These files must use Docker service names (e.g., `http://products:8080/graphql`) for the Gateway to reach subgraphs within the Docker network.
- **Regeneration**: If you change configurations, run `./compose.ps1` in the `src` directory to regenerate `gateway.fgp`, then rebuild the Gateway container.

### Messaging (Wolverine)
- **Transport**: TCP (Ports 5555/5556).
- **Configuration**: `ConnectionStrings__messaging` is left empty in `docker-compose.yml`, triggering the TCP fallback logic in `Program.cs`.

## 2. Cloud Infrastructure Strategy (Bicep)

We manually defined the Bicep infrastructure in the `infra/` folder to support `azd` deployment without Aspire.

### Infrastructure Files
- **`infra/main.bicep`**: Entry point. Creates Resource Group and calls `resources.bicep`.
- **`infra/resources.bicep`**: Provisions:
    - **Log Analytics Workspace**: For centralized logging.
    - **Container Apps Environment**: Hosting environment.
    - **Service Bus Namespace & Queue**: For `orders` messaging.
    - **User Assigned Identity**: For secure access to Service Bus.
    - **Container Registry**: To store images.
    - **Container Apps**: Deploys Gateway, Subgraphs, Workers, and Frontend.
- **`infra/app.bicep`**: Reusable module for defining a Container App.

### Configuration (`azure.yaml`)
The `azure.yaml` file maps each service to its source code and defines it as a `containerapp`. This tells `azd` to build the Docker image and deploy it to the corresponding Container App resource defined in Bicep.

## 3. Deployment Steps (Azure)

1.  **Initialize Environment**:
    ```bash
    azd init
    ```
    Select the subscription and location (e.g., `northeurope`).

2.  **Provision & Deploy**:
    ```bash
    azd up
    ```
    This command will:
    - Provision the Azure resources defined in `infra/`.
    - Build Docker images for all services.
    - Push images to the Azure Container Registry.
    - Deploy images to Azure Container Apps.
    - Configure environment variables (including Service Bus connection strings).

## 4. Verification

### Local
1.  Run `docker-compose up`.
2.  Open [http://localhost:5000/graphql](http://localhost:5000/graphql).
3.  Execute a query that involves orders.
4.  Verify logs in `orders` and `backoffice` containers show message processing via TCP.

### Cloud
1.  Run `azd up`.
2.  Go to the Azure Portal -> Container Apps.
3.  Find the Gateway URL.
4.  Execute a query.
5.  Check the Service Bus "orders" queue metrics to see message activity.
