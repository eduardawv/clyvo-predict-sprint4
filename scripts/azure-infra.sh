#!/usr/bin/env bash
# =================================================================
# CLYVO Predict - Sprint 4 - Infraestrutura no Azure (Azure CLI)
#
# Cria os recursos que o CD (Azure DevOps) usa para o deploy:
#   1. Resource providers da assinatura
#   2. Resource Group
#   3. Azure SQL Server (testa as regioes permitidas ate uma aceitar)
#   4. Firewall do SQL (servicos Azure + seu IPv4)
#   5. Azure SQL Database (PaaS)
#   6. App Service Plan (Linux) + Web App (Java 21)
#
# O DEPLOY NAO e feito aqui: quem publica a aplicacao e a pipeline de CD.
# Ao final o script mostra os valores para o grupo de variaveis do
# Azure DevOps (Library > clyvo-sprint4).
#
# Uso (Git Bash, na raiz do repositorio):
#   az login
#   bash scripts/azure-infra.sh
#
# Pode ser executado de novo: o que ja existe e reaproveitado e a senha
# do banco NAO e alterada (evita divergencia com o Azure DevOps).
# =================================================================
set -Eeuo pipefail
# shellcheck source=scripts/config.sh
source "$(dirname "$0")/config.sh"

trap 'echo -e "${C_ERR}[ERRO]${C_OFF} Falha na linha $LINENO: $BASH_COMMAND" >&2' ERR

# Sucesso se o "show" encontrar o recurso (id nao vazio)
exists() { [[ -n "$("$@" --query id -o tsv 2>/dev/null || true)" ]]; }

# Executa "<funcao> <regiao>" na regiao principal e, se falhar, nas demais.
with_region_fallback() {
  local label=$1 fn=$2 region out
  local ordered=("$LOCATION")
  for region in "${REGIONS[@]}"; do [[ "$region" != "$LOCATION" ]] && ordered+=("$region"); done
  for region in "${ordered[@]}"; do
    if out=$("$fn" "$region" 2>&1); then echo "$region"; return 0; fi
    warn "$label nao foi criado em $region: $(resumo "$out")"
  done
  echo "$out" >&2
  return 1
}

# --------------------------- Pre-checks -------------------------
step "Verificando pre-requisitos"
[[ -f pom.xml && -d src/main/java ]] || fail "Execute na raiz do repositorio (pasta onde esta o pom.xml)."
command -v az >/dev/null 2>&1   || fail "Azure CLI nao encontrado. Instale com: winget install Microsoft.AzureCLI"
command -v curl >/dev/null 2>&1 || fail "curl nao encontrado."
az account show >/dev/null 2>&1 || fail "Voce nao esta logado. Rode: az login"
ok "Assinatura: $(az_out account show --query name -o tsv)"

# --------------------- 1. Resource providers --------------------
step "1/6 Registrando resource providers"
for ns in Microsoft.Sql Microsoft.Web; do
  state=$(az_out provider show -n "$ns" --query registrationState -o tsv 2>/dev/null || echo "NotRegistered")
  if [[ "$state" != "Registered" ]]; then
    echo "    Registrando $ns (pode levar alguns minutos)..."
    az provider register -n "$ns" --wait --only-show-errors
  fi
  ok "$ns"
done

# ------------------------ 2. Resource Group ---------------------
step "2/6 Resource Group $RESOURCE_GROUP"
if [[ "$(az_out group exists -n "$RESOURCE_GROUP")" == "true" ]]; then
  ok "Ja existe, reaproveitando."
else
  az group create -n "$RESOURCE_GROUP" -l "${REGIONS[0]}" -o none --only-show-errors
  ok "Criado."
fi

# ------------------------ 3. Azure SQL Server -------------------
step "3/6 Azure SQL Server $SQL_SERVER"
LOCATION=$(az_out sql server show -g "$RESOURCE_GROUP" -n "$SQL_SERVER" --query location -o tsv 2>/dev/null || true)
if [[ -n "$LOCATION" ]]; then
  ok "Ja existe em $LOCATION. A senha do banco NAO foi alterada."
else
  echo "Defina a senha do administrador do Azure SQL ($SQL_ADMIN_USER)."
  echo "Ela nao e salva em nenhum arquivo. Anote: ela vai para o Azure DevOps como variavel SECRETA (DB_PASSWORD)."
  echo "Regras: 12+ caracteres, comecando com letra ou numero, com MAIUSCULA, minuscula, numero e um simbolo entre @ # ! _ - ."
  read -r -s -p "Senha: " SQL_ADMIN_PASSWORD; echo
  read -r -s -p "Confirme a senha: " SQL_PASS_CONFIRM; echo
  [[ "$SQL_ADMIN_PASSWORD" == "$SQL_PASS_CONFIRM" ]] || fail "As senhas nao conferem."
  RE_ALLOWED='^[A-Za-z0-9][A-Za-z0-9@#!_.-]+$'; RE_UP='[A-Z]'; RE_LOW='[a-z]'; RE_NUM='[0-9]'; RE_SYM='[@#!_.-]'
  [[ ${#SQL_ADMIN_PASSWORD} -ge 12 ]]      || fail "Senha precisa ter 12 ou mais caracteres."
  [[ $SQL_ADMIN_PASSWORD =~ $RE_ALLOWED ]] || fail "Comece com letra ou numero e use apenas letras, numeros e @ # ! _ - ."
  [[ $SQL_ADMIN_PASSWORD =~ $RE_UP && $SQL_ADMIN_PASSWORD =~ $RE_LOW && $SQL_ADMIN_PASSWORD =~ $RE_NUM && $SQL_ADMIN_PASSWORD =~ $RE_SYM ]] \
    || fail "Senha precisa ter maiuscula, minuscula, numero e simbolo."
  [[ "${SQL_ADMIN_PASSWORD,,}" != *"${SQL_ADMIN_USER,,}"* ]] || fail "A senha nao pode conter o nome do usuario ($SQL_ADMIN_USER)."

  for region in "${REGIONS[@]}"; do
    echo "    Tentando a regiao $region..."
    if out=$(az_out sql server create -g "$RESOURCE_GROUP" -n "$SQL_SERVER" -l "$region" \
              --admin-user "$SQL_ADMIN_USER" --admin-password "$SQL_ADMIN_PASSWORD" \
              --minimal-tls-version 1.2 -o none --only-show-errors 2>&1); then
      LOCATION="$region"; break
    fi
    if grep -qiE "RegionDoesNotAllowProvisioning|RequestDisallowedByAzure|not accepting creation|disallowed by Azure|already exists in location|ProvisioningDisabled" <<<"$out"; then
      warn "$region indisponivel para Azure SQL agora. Limpando a tentativa e indo para a proxima..."
      az sql server delete -g "$RESOURCE_GROUP" -n "$SQL_SERVER" --yes -o none --only-show-errors >/dev/null 2>&1 || true
      sleep 15
      continue
    fi
    echo "$out" >&2
    grep -qiE "NameAlreadyExists|already exists" <<<"$out" \
      && fail "O nome '$SQL_SERVER' ja esta em uso no Azure. Altere SQL_SERVER em scripts/config.sh."
    fail "Erro inesperado ao criar o SQL Server (mensagem acima)."
  done
  [[ -n "$LOCATION" ]] || fail "Nenhuma regiao permitida aceitou o Azure SQL agora. Aguarde alguns minutos e rode de novo."
  unset SQL_ADMIN_PASSWORD SQL_PASS_CONFIRM
  ok "Criado em $LOCATION."
fi

# ------------------------ 4. Firewall do SQL --------------------
step "4/6 Firewall do Azure SQL"
fw_rule() {
  local name=$1 ip_start=$2 ip_end=$3 action=create
  if az sql server firewall-rule show -g "$RESOURCE_GROUP" -s "$SQL_SERVER" -n "$name" >/dev/null 2>&1; then action=update; fi
  az sql server firewall-rule "$action" -g "$RESOURCE_GROUP" -s "$SQL_SERVER" -n "$name" \
    --start-ip-address "$ip_start" --end-ip-address "$ip_end" -o none --only-show-errors
}
fw_rule "AllowAzureServices" 0.0.0.0 0.0.0.0
ok "Servicos do Azure (Web App) liberados."
MY_IP=$(curl -s -4 --max-time 10 https://api.ipify.org || true)
if [[ "$MY_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  fw_rule "AllowMyIP" "$MY_IP" "$MY_IP"
  ok "Seu IPv4 $MY_IP liberado (terminal de consultas do banco)."
else
  warn "Nao detectei seu IPv4. Depois rode: bash scripts/azure-liberar-ip.sh"
fi

# ------------------------ 5. SQL Database -----------------------
step "5/6 Azure SQL Database $SQL_DB ($DB_SKU)"
if exists az sql db show -g "$RESOURCE_GROUP" -s "$SQL_SERVER" -n "$SQL_DB"; then
  ok "Ja existe, reaproveitando."
else
  # Backup "Local": regioes sem par (ex.: Mexico Central) nao aceitam backup geo-redundante
  az sql db create -g "$RESOURCE_GROUP" -s "$SQL_SERVER" -n "$SQL_DB" \
    --service-objective "$DB_SKU" --backup-storage-redundancy Local -o none --only-show-errors
  ok "Criado. As tabelas sao criadas pelo Flyway quando a aplicacao sobe (deploy do CD)."
fi

# ------------------ 6. App Service Plan + Web App ---------------
step "6/6 App Service Plan $APP_PLAN ($PLAN_SKU Linux) e Web App $WEB_APP"
create_plan() {
  az appservice plan create -g "$RESOURCE_GROUP" -n "$APP_PLAN" -l "$1" --sku "$PLAN_SKU" --is-linux -o none --only-show-errors
}
if exists az appservice plan show -g "$RESOURCE_GROUP" -n "$APP_PLAN"; then
  ok "Plano ja existe, reaproveitando."
else
  PLAN_REGION=$(with_region_fallback "App Service Plan" create_plan) || fail "Nao foi possivel criar o App Service Plan."
  ok "Plano criado em $PLAN_REGION."
fi

if exists az webapp show -g "$RESOURCE_GROUP" -n "$WEB_APP"; then
  ok "Web App ja existe, reaproveitando."
else
  if ! out=$(az_out webapp create -g "$RESOURCE_GROUP" -n "$WEB_APP" -p "$APP_PLAN" --runtime "$JAVA_RUNTIME" -o none --only-show-errors 2>&1); then
    echo "$out" >&2
    grep -qiE "already exists|not available" <<<"$out" && fail "O nome '$WEB_APP' ja esta em uso no Azure. Altere WEB_APP em scripts/config.sh."
    fail "Erro ao criar o Web App (mensagem acima)."
  fi
  ok "Web App criado (runtime $JAVA_RUNTIME)."
fi
az webapp update -g "$RESOURCE_GROUP" -n "$WEB_APP" --https-only true -o none --only-show-errors
az webapp config set -g "$RESOURCE_GROUP" -n "$WEB_APP" --always-on true --ftps-state Disabled --min-tls-version 1.2 -o none --only-show-errors
az webapp log config -g "$RESOURCE_GROUP" -n "$WEB_APP" --application-logging filesystem \
  --docker-container-logging filesystem --level information -o none --only-show-errors
ok "HTTPS obrigatorio, Always On, FTP desabilitado, TLS 1.2 e logs habilitados."

# --------------------------- Resumo -----------------------------
echo
echo -e "${C_OK}================================================================${C_OFF}"
echo -e "${C_OK}  CLYVO Predict - Sprint 4 - infraestrutura pronta${C_OFF}"
echo -e "${C_OK}================================================================${C_OFF}"
echo "  Resource Group : $RESOURCE_GROUP ($LOCATION)"
echo "  Azure SQL      : $SQL_FQDN / $SQL_DB"
echo "  Web App        : $APP_URL  (a API aparece depois do primeiro CD)"
echo
echo "  Copie para o Azure DevOps > Pipelines > Library > grupo clyvo-sprint4:"
echo "  ----------------------------------------------------------------"
echo "  RESOURCE_GROUP = $RESOURCE_GROUP"
echo "  WEB_APP_NAME   = $WEB_APP"
echo "  DB_URL         = $JDBC_URL"
echo "  DB_USER        = $SQL_ADMIN_USER        (marcar o cadeado: secreta)"
echo "  DB_PASSWORD    = <a senha que voce digitou> (marcar o cadeado: secreta)"
echo "  ----------------------------------------------------------------"
echo "  Service connection: escopo no resource group $RESOURCE_GROUP"
echo
