# Azure PoC Runbook

## Deploy

```bash
az login
az account set --subscription "<subscription-id>"
export SQL_ADMINISTRATOR_PASSWORD="<strong-password>"
export ORDER_API_BACKEND_KEY="<random-backend-key>"
./scripts/deploy.sh
```

GitHub Actions production deployments must run from `refs/heads/master`. The workflow signs the worker image after the HIGH/CRITICAL Trivy gate passes and verifies the signature before updating Container Apps by digest.

## Submit Test Order

Replace the API URL with the API Management gateway URL after deployment.

```bash
curl -X POST "https://<apim-name>.azure-api.net/orders" \
  -H "Ocp-Apim-Subscription-Key: <subscription-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "customerId": "cust-1001",
    "sku": "demo-widget",
    "quantity": 2
  }'
```

## Bootstrap SQL Managed Identity

Before the API can write order rows, connect to Azure SQL as an administrator and run `scripts/sql-managed-identity-bootstrap.sql`. The script creates the table if it is missing, creates the App Service managed identity user, and grants only `INSERT` through the `app_order_writer` role.

```sql
-- See scripts/sql-managed-identity-bootstrap.sql
```

If `CREATE USER ... FROM EXTERNAL PROVIDER` fails, confirm the SQL server has a Microsoft Entra administrator configured. The Bicep template supports this through `sqlEntraAdministratorLogin` and `sqlEntraAdministratorObjectId`.

## Investigate

- API logs: Application Insights transaction search filtered by `OrderApi`.
- Worker logs: Container Apps logs and Application Insights traces filtered by `OrderWorker`.
- Function logs: Function App invocation logs and Application Insights traces filtered by `OrderFunctions`.
- Queue health: Service Bus queue active/dead-letter message count.
- Event delivery: Event Grid subscription delivery metrics.
- Security gate: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-security.ps1`.
- Worker image gate: GitHub Actions Trivy and cosign steps before Container Apps update.

## Cleanup

```bash
az group delete --name rg-azure-poc --yes --no-wait
```

## Production Hardening Gaps

- Replace APIM subscription-key authentication with the target real API authentication and authorization model.
- Add SQL migrations through a controlled release identity if the PoC becomes a product path.
- Add dead-letter handling and replay tooling.
- Add dashboards, alerts, SLOs, and cost budgets.
- Add automated integration tests against deployed infrastructure.
