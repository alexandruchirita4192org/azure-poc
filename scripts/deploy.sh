#!/usr/bin/env bash
set -euo pipefail

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-azure-poc}"
LOCATION="${LOCATION:-westeurope}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-azure-poc}"

: "${SQL_ADMINISTRATOR_PASSWORD:?Set SQL_ADMINISTRATOR_PASSWORD before deploying.}"
: "${ORDER_API_BACKEND_KEY:?Set ORDER_API_BACKEND_KEY before deploying.}"

SQL_ENTRA_ADMIN_LOGIN="${SQL_ENTRA_ADMIN_LOGIN:-}"
SQL_ENTRA_ADMIN_OBJECT_ID="${SQL_ENTRA_ADMIN_OBJECT_ID:-}"

if [[ -z "$SQL_ENTRA_ADMIN_LOGIN" || -z "$SQL_ENTRA_ADMIN_OBJECT_ID" ]]; then
  if az ad signed-in-user show >/dev/null 2>&1; then
    SQL_ENTRA_ADMIN_LOGIN="${SQL_ENTRA_ADMIN_LOGIN:-$(az ad signed-in-user show --query userPrincipalName -o tsv)}"
    SQL_ENTRA_ADMIN_OBJECT_ID="${SQL_ENTRA_ADMIN_OBJECT_ID:-$(az ad signed-in-user show --query id -o tsv)}"
  fi
fi

az group create --name "$RESOURCE_GROUP" --location "$LOCATION"

az deployment group create \
  --name "$DEPLOYMENT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --template-file infra/main.bicep \
  --parameters infra/main.parameters.json location="$LOCATION" sqlAdministratorPassword="$SQL_ADMINISTRATOR_PASSWORD" orderApiBackendKey="$ORDER_API_BACKEND_KEY" sqlEntraAdministratorLogin="$SQL_ENTRA_ADMIN_LOGIN" sqlEntraAdministratorObjectId="$SQL_ENTRA_ADMIN_OBJECT_ID"

az deployment group show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$DEPLOYMENT_NAME" \
  --query properties.outputs
