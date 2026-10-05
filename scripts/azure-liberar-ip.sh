#!/usr/bin/env bash
# =================================================================
# Libera o IPv4 atual no firewall do Azure SQL.
# Use se trocar de rede (casa/FIAP) e o terminal do banco nao conectar.
# Uso (Git Bash):  bash scripts/azure-liberar-ip.sh
# =================================================================
set -Eeuo pipefail
# shellcheck source=scripts/config.sh
source "$(dirname "$0")/config.sh"

RULE="AllowMyIP"
MY_IP=$(curl -s -4 --max-time 10 https://api.ipify.org || true)
[[ "$MY_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Nao consegui descobrir seu IPv4."

ACTION=create
az sql server firewall-rule show -g "$RESOURCE_GROUP" -s "$SQL_SERVER" -n "$RULE" >/dev/null 2>&1 && ACTION=update
az sql server firewall-rule "$ACTION" -g "$RESOURCE_GROUP" -s "$SQL_SERVER" -n "$RULE" \
  --start-ip-address "$MY_IP" --end-ip-address "$MY_IP" -o none --only-show-errors
ok "IPv4 $MY_IP liberado no firewall do $SQL_SERVER."
