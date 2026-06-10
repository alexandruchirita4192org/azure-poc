# Azure PoC Runbook

## Deploy

```bash
az login
az account set --subscription "<subscription-id>"
az group create --name rg-azure-poc --location westeurope
az deployment group create \
  --resource-group rg-azure-poc \
  --template-file infra/main.bicep \
  --parameters infra/main.parameters.json
```

## Submit Test Order

Replace the API URL with the API Management gateway URL after deployment.

```bash
curl -X POST "https://<apim-name>.azure-api.net/orders" \
  -H "Content-Type: application/json" \
  -d '{
    "customerId": "cust-1001",
    "sku": "demo-widget",
    "quantity": 2
  }'
```

## Bootstrap SQL Managed Identity

Before the API can create and write the PoC `Orders` table, connect to Azure SQL as an administrator and run:

```sql
CREATE USER [app-REPLACE-WITH-APP-SERVICE-NAME] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [app-REPLACE-WITH-APP-SERVICE-NAME];
ALTER ROLE db_datawriter ADD MEMBER [app-REPLACE-WITH-APP-SERVICE-NAME];
ALTER ROLE db_ddladmin ADD MEMBER [app-REPLACE-WITH-APP-SERVICE-NAME];
```

For a production system, replace `db_ddladmin` with migrations run by a controlled deployment identity.

If `CREATE USER ... FROM EXTERNAL PROVIDER` fails, confirm the SQL server has a Microsoft Entra administrator configured. The Bicep template supports this through `sqlEntraAdministratorLogin` and `sqlEntraAdministratorObjectId`.

## Investigate

- API logs: Application Insights transaction search filtered by `OrderApi`.
- Worker logs: Container Apps logs and Application Insights traces filtered by `OrderWorker`.
- Function logs: Function App invocation logs and Application Insights traces filtered by `OrderFunctions`.
- Queue health: Service Bus queue active/dead-letter message count.
- Event delivery: Event Grid subscription delivery metrics.

## Cleanup

```bash
az group delete --name rg-azure-poc --yes --no-wait
```

## Production Hardening Gaps

- Add real API authentication and authorization.
- Add private endpoints and network restrictions.
- Add SQL migrations through a controlled release step.
- Add dead-letter handling and replay tooling.
- Add dashboards, alerts, SLOs, and cost budgets.
- Add automated integration tests against deployed infrastructure.
