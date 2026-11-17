#!/usr/bin/env bash
# One-time: create the Storage Account that holds this stack's Terraform state,
# then write backend.hcl. Auth is Entra ID (your az login), no access keys.
set -euo pipefail

LOCATION="${LOCATION:-francecentral}"
RG="${RG:-potti-ci-tfstate-rg}"
SA="${SA:-potticitfstate$(openssl rand -hex 3)}"
cd "$(dirname "$0")/.."

az group create -n "$RG" -l "$LOCATION" -o none
az storage account create -n "$SA" -g "$RG" -l "$LOCATION" \
    --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 \
    --allow-blob-public-access false --allow-shared-key-access false -o none
az storage account blob-service-properties update -n "$SA" -g "$RG" \
    --enable-versioning true -o none

me=$(az ad signed-in-user show --query id -o tsv)
az role assignment create --assignee "$me" --role "Storage Blob Data Contributor" \
    --scope "$(az storage account show -n "$SA" -g "$RG" --query id -o tsv)" -o none

# Role assignments can take a minute to propagate.
for _ in $(seq 1 12); do
    az storage container create -n tfstate --account-name "$SA" --auth-mode login -o none 2>/dev/null && break
    sleep 10
done

cat > backend.hcl <<HCL
resource_group_name  = "$RG"
storage_account_name = "$SA"
container_name       = "tfstate"
key                  = "azure-runners.tfstate"
use_azuread_auth     = true
HCL
echo "backend.hcl written (storage account: $SA)"
