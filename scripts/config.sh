# shellcheck shell=bash
# shellcheck disable=SC2034  # variaveis usadas pelos scripts que carregam este arquivo
# =================================================================
# CLYVO Predict - Sprint 4 - configuracao central dos scripts
# Todos os nomes de recursos ficam AQUI. Os demais scripts carregam
# este arquivo; para mudar um nome, altere so este arquivo.
# Os mesmos nomes vao para o grupo de variaveis clyvo-sprint4 do
# Azure DevOps (WEB_APP_NAME, RESOURCE_GROUP, DB_URL, DB_USER).
# =================================================================

RM="rm564434"
RESOURCE_GROUP="rg-clyvo-sprint4"
SQL_SERVER="clyvo-sprint4-sql-${RM}"
SQL_DB="clyvodb"
SQL_ADMIN_USER="clyvoadmin"
APP_PLAN="clyvo-sprint4-plan"
WEB_APP="clyvo-sprint4-${RM}"
JAVA_RUNTIME="JAVA:21-java21"
PLAN_SKU="B1"
DB_SKU="Basic"

# Regioes liberadas pela policy da assinatura FIAP. A primeira que aceitar
# o Azure SQL e usada para todos os recursos.
# Para forcar uma regiao: AZ_REGION=eastus2 bash scripts/azure-infra.sh
REGIONS=(mexicocentral eastus2 eastus southcentralus southafricanorth)
if [[ -n "${AZ_REGION:-}" ]]; then REGIONS=("$AZ_REGION"); fi

APP_URL="https://${WEB_APP}.azurewebsites.net"
SQL_FQDN="${SQL_SERVER}.database.windows.net"
JDBC_URL="jdbc:sqlserver://${SQL_FQDN}:1433;database=${SQL_DB};encrypt=true;trustServerCertificate=false;hostNameInCertificate=*.database.windows.net;loginTimeout=30"

# Git Bash (Windows) converte argumentos que comecam com "/" em caminhos
# do Windows e corrompe IDs do Azure. Isto desliga a conversao.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"

# No Windows o az devolve linhas com \r (CRLF); toda captura passa por aqui.
az_out() { az "$@" | tr -d '\r'; }

C_INFO='\033[0;36m'; C_OK='\033[0;32m'; C_WARN='\033[1;33m'; C_ERR='\033[0;31m'; C_OFF='\033[0m'
step() { echo; echo -e "${C_INFO}==> $*${C_OFF}"; }
ok()   { echo -e "${C_OK}[ OK ]${C_OFF} $*"; }
warn() { echo -e "${C_WARN}[AVISO]${C_OFF} $*" >&2; }
fail() { echo -e "${C_ERR}[ERRO]${C_OFF} $*" >&2; exit 1; }

# Primeira linha nao vazia de uma mensagem de erro do az (para avisos curtos)
resumo() { printf '%s\n' "$1" | tr -d '\r' | grep -m1 -v '^[[:space:]]*$' | cut -c1-200 || true; }
