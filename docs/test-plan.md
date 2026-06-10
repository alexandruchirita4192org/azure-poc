# PoC Test Plan

## Smoke Tests

1. Deploy Bicep successfully to a clean resource group.
2. Confirm App Service, Function App, Container App, SQL, Cosmos DB, Storage, Service Bus, Event Grid, Key Vault, Application Insights, and API Management resources exist.
3. Submit an order through API Management.
4. Confirm `202 Accepted` response with an order id.
5. Confirm SQL contains the order status row.
6. Confirm Cosmos DB contains the order document.
7. Confirm Blob Storage contains the archived payload.
8. Confirm Service Bus queue message is consumed by the Container Apps worker.
9. Confirm Event Grid delivery invokes the Azure Function.
10. Confirm Application Insights shows traces from API, worker, and function.

## Failure Tests

1. Disable Service Bus access for the worker identity and confirm processing failures are visible in Application Insights.
2. Send malformed order payload and confirm the API returns `400 Bad Request`.
3. Temporarily block Cosmos DB access and confirm the API fails safely without acknowledging the order.
4. Publish an invalid Event Grid event and confirm the Function logs a validation warning.

## Operational Checks

1. Verify Key Vault references resolve in App Service configuration.
2. Verify managed identities have only the required role assignments.
3. Verify Application Insights dependency tracking captures SQL, Storage, Cosmos DB, Service Bus, and Event Grid calls.
4. Verify resource names, tags, and location match the parameters.

## Exit Criteria

- The happy path works twice after a fresh deployment.
- At least one intentional failure is observable without shell access to the app hosts.
- Cleanup deletes the whole resource group without orphaned resources.
