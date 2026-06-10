# ADR-001: Thin Vertical Slice Across Azure Integration Services

## Status

Proposed

## Context

The PoC needs to demonstrate a representative Azure application using API ingress, synchronous persistence, asynchronous processing, event distribution, secure configuration, observability, and CI/CD. The service list is intentionally broad, so the implementation must avoid becoming a full product build.

## Decision

Use an order intake workflow:

1. API Management exposes `POST /orders`.
2. App Service hosts a .NET API that accepts the request.
3. The API persists normalized state in Azure SQL.
4. The API stores the full document in Cosmos DB.
5. The API archives the submitted payload in Azure Blob Storage.
6. The API sends a processing message to Service Bus.
7. The API publishes an `OrderCreated` event to Event Grid.
8. Azure Functions handles Event Grid lifecycle events.
9. Azure Container Apps runs a Service Bus worker.
10. Application Insights receives telemetry from all compute services.
11. Key Vault plus managed identity is the default configuration and secret access pattern.

## Consequences

Positive:

- Every requested service has a concrete role.
- The flow is easy to test manually and through automation.
- Managed identity and observability are part of the first slice.
- Async processing can be extended later without changing the API contract.

Tradeoffs:

- The PoC contains more Azure resources than a minimal order API would normally need.
- Running costs are higher than a single-service spike.
- The sample worker and function are intentionally small and prove integration rather than business complexity.

## Follow-up Decisions

- Decide whether the long-term API hosting target should be App Service, Container Apps, or both.
- Decide whether Event Grid is needed if Service Bus already carries all operational work.
- Choose a real authentication model for API Management, such as Entra ID, subscription keys, mTLS, or OAuth2.
- Add private networking and firewall rules if the PoC is promoted beyond an isolated sandbox.
