# Updating `gateway.fgp` without redeploying the Gateway

## Goal
Enable HotChocolate Fusion Gateway schema recomposition (updating `gateway.fgp`) **without redeploying** the Gateway container.

Constraints from the architecture:
- The Gateway may run with **multiple replicas**.
- Updates must be **multicast/broadcast** (no “send to gateway X”).
- When a **new Gateway replica starts**, it must **fetch the latest** `gateway.fgp` automatically.
- The update trigger must work:
  - **Locally** (docker-compose / dotnet run)
  - On **Azure Container Apps (ACA)**
- Use the existing WebSocket capability already enabled in the Gateway (`app.UseWebSockets()` and GraphQL subscriptions).

## Current state (what we already have)
- Gateway loads Fusion config from file:
  - `AddFusionGatewayServer().ConfigureFromFile("gateway.fgp")`
- Gateway runs a background watcher:
  - `FusionReloadService` watches the `gateway.fgp` file and calls `_executorResolver.EvictRequestExecutor()`.
  - This means: if we can update the file inside the container, the Gateway can reload **without restart**.

The missing piece is an **in-band distribution channel** to deliver the latest `gateway.fgp` to all running Gateway replicas and to new replicas when they come online.

## Proposed design: `nitro-schema-api`
Introduce a small internal service called **`nitro-schema-api`**.

Responsibilities:
1. **Source of truth** for the current composed `gateway.fgp` (versioned).
2. Maintain a **WebSocket hub**:
   - Gateways connect as WebSocket clients.
   - Nitro broadcasts “new FGP available” to all connected gateways.
3. Provide a **bootstrap path** for new gateways:
   - On connect, gateway receives the latest `gateway.fgp` (or can request it).
4. Accept an **external trigger** *via the Gateway’s existing WebSocket/GraphQL channel*:
   - External user talks to the public Gateway.
   - Gateway forwards the trigger to Nitro over the already-established internal WebSocket connection.

### Why an internal service?
- Nitro can remain **internal-only** on ACA (no public ingress).
- External operators can still trigger updates through the public Gateway (which is already exposed and already supports WebSockets).

## Data model and versioning
Nitro should store a versioned record:
- `version` (monotonic integer) or `etag` (sha256 hash of content)
- `createdAt`
- `createdBy` (optional)
- `content` (the `gateway.fgp` text)

Recommended persistence:
- Use the existing Postgres Flexible Server.
- Table (example): `gateway_fgp` with `id=1` as the “current pointer”, plus a history table `gateway_fgp_versions`.

Why persist?
- If Nitro restarts, it can immediately serve the last known `gateway.fgp`.
- New Gateways can always bootstrap even if there’s been no “recent broadcast”.

## WebSocket protocol (Nitro ⇄ Gateways)
This is a simple JSON message protocol over WebSocket.

### Messages
**Gateway → Nitro**
- `HELLO`
  - `{ "type": "HELLO", "gatewayInstanceId": "<guid>", "currentEtag": "<optional>" }`
- `GET_LATEST`
  - `{ "type": "GET_LATEST" }`
- `PUBLISH`
  - Sent by a Gateway *acting as a relay* when an operator triggers an update through the public Gateway.
  - `{ "type": "PUBLISH", "token": "<admin-token>", "fgp": "<base64>", "etag": "<sha256>", "meta": { ... } }`

**Nitro → Gateway (multicast)**
- `LATEST`
  - `{ "type": "LATEST", "etag": "<sha256>", "fgp": "<base64>", "version": 42 }`
- `FGP_UPDATED`
  - Broadcast after Nitro accepts a publish.
  - `{ "type": "FGP_UPDATED", "etag": "<sha256>", "fgp": "<base64>", "version": 43 }`
- `ERROR`
  - `{ "type": "ERROR", "message": "..." }`

### Bootstrap behavior (new Gateway)
On startup, each Gateway:
1. Connects to Nitro WebSocket.
2. Sends `HELLO`.
3. Nitro responds with `LATEST` (always send full payload to make startup deterministic).
4. Gateway writes `gateway.fgp` atomically, which triggers `FusionReloadService`.

### Update behavior (multicast)
When Nitro receives a new composed file:
1. Persist it (transaction), compute `etag`.
2. Broadcast `FGP_UPDATED` with full payload to **all connected gateways**.
3. Every Gateway writes the file and reloads.

No targeting is required; this is true multicast.

## Triggering updates when Nitro is internal-only
We trigger via the **public Gateway**, using the existing GraphQL + WebSocket channel.

### Option A (recommended): Add a protected GraphQL mutation on Gateway
Add a mutation on the Gateway (public) like:

```graphql
mutation PublishGatewayFgp($fgpBase64: String!) {
  publishGatewayFgp(fgpBase64: $fgpBase64) {
    etag
    version
  }
}
```

Implementation idea:
- The mutation validates an admin token (header or argument).
- The Gateway maintains a long-lived internal WebSocket connection to Nitro.
- The Gateway forwards the `PUBLISH` message to Nitro over that internal WS.
- Nitro persists and broadcasts `FGP_UPDATED` to all gateways.

Benefits:
- No public ingress for Nitro.
- Operators use the already-existing public endpoint (`/graphql`).

### Option B: Use the existing operator WebSocket session
If the operator is already connected via GraphQL subscriptions to the Gateway:
- Use the same connection to send the mutation.
- The rest remains the same (Gateway relays to Nitro).

## Where does the new FGP come from?
Nitro can support either (or both) of these composition sources:

1. **Push model (simplest):**
   - The operator (or CI pipeline) composes `gateway.fgp` externally (using `dotnet fusion compose` like we do today).
   - The operator publishes the resulting `gateway.fgp` content via the `publishGatewayFgp` mutation.

2. **Pull model (more automation):**
   - Nitro can run the Fusion composition itself.
   - It periodically pulls subgraph schemas/endpoints, packs them, composes, and then broadcasts.
   - This is more complex (requires the dotnet toolchain and access to subgraphs), but can be added later.

This document assumes **push model** first.

## Gateway-side implementation details
Each Gateway replica adds a background client:
- `NitroSchemaClientService` (new)
  - Connects to `NITRO_SCHEMA_WS` (e.g., `ws://nitro-schema-api:8080/ws` locally, `wss://nitro-schema-api.internal.../ws` on ACA if TLS is used internally).
  - On `LATEST` / `FGP_UPDATED`:
    1. Decode base64 payload.
    2. Write to a temp file next to `gateway.fgp`.
    3. Replace `gateway.fgp` atomically.
    4. Optionally call `_executorResolver.EvictRequestExecutor()` immediately (the file watcher will also handle it).
  - Auto-reconnect with exponential backoff.

Atomic write pattern (to avoid partial reads):
- Write `gateway.fgp.tmp`
- `File.Move(tmp, gateway.fgp, overwrite: true)`

## Local development wiring
- Run Nitro on docker-compose network with internal name `nitro-schema-api`.
- Configure Gateway env var:
  - `NITRO_SCHEMA_WS=ws://nitro-schema-api:8080/ws`
- Operator triggers publish:
  - Call Gateway mutation from Banana Cake Pop / Postman / custom CLI.

## ACA wiring
- Deploy `nitro-schema-api` as a Container App with **internal ingress**.
- Gateway connects using the internal FQDN:
  - `NITRO_SCHEMA_WS=ws://nitro-schema-api.internal.<env>.<region>.azurecontainerapps.io/ws`

Trigger path:
- Operator calls the public Gateway (`https://gateway.../graphql`) mutation.
- Gateway relays to Nitro internally.
- Nitro broadcasts to all Gateway replicas.

## Security
Minimum viable controls:
- `publishGatewayFgp` requires a shared `ADMIN_TOKEN` (stored as ACA secret and injected as env var).
- Nitro validates the token on `PUBLISH`.
- Gateway validates the token before relaying.

Hardening options (later):
- mTLS between Gateway and Nitro.
- Signed payloads with rotating keys.
- RBAC via Entra ID and JWT validation on the Gateway mutation.

## Failure modes and expected behavior
- **Nitro down:**
  - Gateways keep serving last loaded schema.
  - Gateways retry WS connect.
- **Gateway down / restarting:**
  - On reconnect, Nitro sends `LATEST` so the Gateway always catches up.
- **Multiple Gateway replicas:**
  - Every replica connects and receives broadcasts.
  - No replica identity is required for routing.
- **Nitro scaled to >1 replica:**
  - Avoid initially; keep Nitro `minReplicas=maxReplicas=1`.
  - If scaling is required, add leader election (e.g., Postgres advisory lock) so only one instance broadcasts.

## Acceptance criteria
- Updating `gateway.fgp` can be triggered through the public Gateway without redeploying it.
- All Gateway replicas reload within seconds (multicast).
- A newly started Gateway replica always fetches the latest `gateway.fgp` and serves the current schema.
- Works locally and on ACA using the same protocol (only endpoint changes via env vars).
