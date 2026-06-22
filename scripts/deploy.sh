#!/usr/bin/env bash
set -euo pipefail

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-azure-poc}"
LOCATION="${LOCATION:-westeurope}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-azure-poc}"

: "${SQL_ADMINISTRATOR_PASSWORD:?Set SQL_ADMINISTRATOR_PASSWORD before deploying.}"
: "${ORDER_API_BACKEND_KEY:?Set ORDER_API_BACKEND_KEY before deploying.}"

az group create --name "$RESOURCE_GROUP" --location "$LOCATION"

az deployment group create \
  --name "$DEPLOYMENT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --template-file infra/main.bicep \
  --parameters infra/main.parameters.json location="$LOCATION" sqlAdministratorPassword="$SQL_ADMINISTRATOR_PASSWORD" orderApiBackendKey="$ORDER_API_BACKEND_KEY"

az deployment group show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$DEPLOYMENT_NAME" \
  --query properties.outputs
