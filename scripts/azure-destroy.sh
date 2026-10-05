#!/usr/bin/env bash
# =================================================================
# CLYVO Predict - Sprint 4 - Remove TODOS os recursos do Azure
# Rode so depois da entrega/correcao para nao consumir creditos.
# Uso (Git Bash):  bash scripts/azure-destroy.sh
# =================================================================
set -Eeuo pipefail
# shellcheck source=scripts/config.sh
source "$(dirname "$0")/config.sh"

az account show >/dev/null 2>&1 || fail "Rode az login primeiro."

if [[ "$(az_out group exists -n "$RESOURCE_GROUP")" != "true" ]]; then
  ok "Resource Group $RESOURCE_GROUP nao existe. Nada para remover."
  exit 0
fi

echo "Recursos que serao REMOVIDOS:"
az resource list -g "$RESOURCE_GROUP" --query "[].{Nome:name, Tipo:type, Regiao:location}" -o table
echo
warn "Esta acao apaga o banco e todos os dados. As pipelines de CD vao falhar ate a infra ser recriada."
read -r -p "Digite o nome do resource group para confirmar ($RESOURCE_GROUP): " CONFIRM
[[ "$CONFIRM" == "$RESOURCE_GROUP" ]] || { echo "Cancelado."; exit 1; }

echo "Removendo o Resource Group $RESOURCE_GROUP (leva de 3 a 10 minutos)..."
az group delete -n "$RESOURCE_GROUP" --yes --only-show-errors

if [[ "$(az_out group exists -n "$RESOURCE_GROUP")" == "false" ]]; then
  ok "Todos os recursos foram removidos."
else
  warn "O grupo ainda aparece. Confira no portal em alguns minutos."
fi
