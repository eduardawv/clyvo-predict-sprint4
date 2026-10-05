#!/usr/bin/env bash
# =================================================================
# CLYVO Predict - Sprint 4 - PLANO B: agente proprio (self-hosted)
#
# Use SOMENTE se a organizacao do Azure DevOps nao tiver paralelismo
# hospedado (erro "No hosted parallelism has been purchased or granted"
# ou Organization settings > Parallel jobs > Microsoft-hosted = 0).
# O agente self-hosted e gratuito no Azure DevOps.
#
# Cria uma VM Ubuntu 24.04 no mesmo resource group, instala JDK 21,
# Maven e o agente do Azure Pipelines (pool Default) via cloud-init.
# A VM nao abre nenhuma porta de entrada: o agente so faz conexoes de saida.
#
# Pre-requisitos:
#   - bash scripts/azure-infra.sh ja executado
#   - PAT do Azure DevOps (User settings > Personal access tokens) com o
#     escopo "Agent Pools (Read & manage)" e validade curta (7 dias)
#
# Uso (Git Bash, na raiz do repositorio):  bash scripts/azure-agente-vm.sh
# Depois: troque "vmImage: ubuntu-24.04" por "name: Default" nos dois YAML.
# =================================================================
set -Eeuo pipefail
# shellcheck source=scripts/config.sh
source "$(dirname "$0")/config.sh"

AGENT_VM="clyvo-agente-${RM}"
AGENT_NAME="clyvo-agente-vm"
VM_IMAGE="Canonical:ubuntu-24_04-lts:server:latest"
VM_SIZES=(Standard_B2s Standard_B2ms Standard_D2s_v5 Standard_B1ms)
CLOUD_INIT=".agent-cloud-init.tmp"

trap 'echo -e "${C_ERR}[ERRO]${C_OFF} Falha na linha $LINENO: $BASH_COMMAND" >&2' ERR
trap 'rm -f "$CLOUD_INIT"' EXIT

json_field() { grep -o "\"$1\": *\"[^\"]*\"" | head -1 | cut -d'"' -f4; }
json_num()   { grep -o "\"$1\": *[0-9][0-9]*" | head -1 | grep -o '[0-9]*$'; }

# --------------------------- Pre-checks -------------------------
step "Verificando pre-requisitos"
[[ -f pom.xml ]] || fail "Execute na raiz do repositorio."
az account show >/dev/null 2>&1 || fail "Rode az login primeiro."
[[ "$(az_out group exists -n "$RESOURCE_GROUP")" == "true" ]] || fail "Resource group $RESOURCE_GROUP nao existe. Rode antes: bash scripts/azure-infra.sh"
RG_LOCATION=$(az_out sql server show -g "$RESOURCE_GROUP" -n "$SQL_SERVER" --query location -o tsv 2>/dev/null || true)
RG_LOCATION=${RG_LOCATION:-${REGIONS[0]}}

read -r -p "URL da organizacao (ex.: https://dev.azure.com/nome-da-org): " ORG_URL
ORG_URL="${ORG_URL%/}"
[[ "$ORG_URL" =~ ^https://dev\.azure\.com/[^/]+$ ]] || fail "Use o formato https://dev.azure.com/<organizacao>."
read -r -s -p "PAT com escopo Agent Pools (Read & manage) - nao aparece: " PAT; echo
[[ -n "$PAT" ]] || fail "PAT vazio."

step "Conferindo o PAT e o pool Default"
resp=$(curl -s -u ":$PAT" -w $'\n%{http_code}' "$ORG_URL/_apis/distributedtask/pools?poolName=Default&api-version=7.1" || true)
code=${resp##*$'\n'}; body=${resp%$'\n'*}
[[ "$code" == "200" && "$body" == *'"count"'* ]] || fail "PAT invalido ou sem permissao (HTTP $code). Gere um PAT com escopo Agent Pools (Read & manage)."
POOL_ID=$(json_num id <<<"$body")
[[ -n "$POOL_ID" ]] || fail "Pool Default nao encontrado na organizacao."
ok "PAT valido. Pool Default id=$POOL_ID."

step "Descobrindo o pacote do agente para Linux"
AGENT_URL=""
for ver in 7.1-preview.1 6.0-preview 5.0-preview; do
  AGENT_URL=$(curl -s -u ":$PAT" "$ORG_URL/_apis/distributedtask/packages/agent?platform=linux-x64&\$top=1&api-version=$ver" | json_field downloadUrl || true)
  [[ -n "$AGENT_URL" ]] && break
done
if [[ -z "$AGENT_URL" ]]; then
  TAG=$(curl -s https://api.github.com/repos/microsoft/azure-pipelines-agent/releases/latest | json_field tag_name || true)
  VER=${TAG#v}
  [[ -n "$VER" ]] && AGENT_URL="https://download.agent.dev.azure.com/agent/${VER}/vsts-agent-linux-x64-${VER}.tar.gz"
fi
[[ "$AGENT_URL" == https://*linux-x64*.tar.gz ]] || fail "Nao consegui descobrir o link do agente. Mande a tela para a equipe."
ok "$AGENT_URL"

# ----------------------- cloud-init da VM -----------------------
umask 077
cat > "$CLOUD_INIT" <<EOF
#cloud-config
package_update: true
packages:
  - openjdk-21-jdk-headless
  - maven
  - zip
  - unzip
  - curl
  - git
  - python3
write_files:
  - path: /opt/azagent-setup.sh
    permissions: '0700'
    content: |
      #!/bin/bash
      set -euo pipefail
      id azagent >/dev/null 2>&1 || useradd -m -s /bin/bash azagent
      mkdir -p /opt/azagent
      cd /opt/azagent
      curl -fsSL -o agent.tar.gz "${AGENT_URL}"
      tar zxf agent.tar.gz
      rm -f agent.tar.gz
      ./bin/installdependencies.sh
      echo "JAVA_HOME_21_X64=/usr/lib/jvm/java-21-openjdk-amd64" >> .env
      chown -R azagent:azagent /opt/azagent
      sudo -u azagent ./config.sh --unattended --url "${ORG_URL}" --auth pat --token "${PAT}" --pool Default --agent "${AGENT_NAME}" --acceptTeeEula --replace
      ./svc.sh install azagent
      ./svc.sh start
      rm -f /opt/azagent-setup.sh
runcmd:
  - [ bash, /opt/azagent-setup.sh ]
EOF

# ------------------------ Providers -----------------------------
step "Registrando providers de VM e rede"
for ns in Microsoft.Compute Microsoft.Network; do
  state=$(az_out provider show -n "$ns" --query registrationState -o tsv 2>/dev/null || echo "NotRegistered")
  [[ "$state" == "Registered" ]] || az provider register -n "$ns" --wait --only-show-errors
  ok "$ns"
done

# ------------------------ Criacao da VM -------------------------
cleanup_attempt() {
  az vm delete -g "$RESOURCE_GROUP" -n "$AGENT_VM" --yes -o none --only-show-errors >/dev/null 2>&1 || true
  az network nic delete -g "$RESOURCE_GROUP" -n "${AGENT_VM}VMNic" -o none --only-show-errors >/dev/null 2>&1 || true
  az network public-ip delete -g "$RESOURCE_GROUP" -n "${AGENT_VM}-ip" -o none --only-show-errors >/dev/null 2>&1 || true
  az network nsg delete -g "$RESOURCE_GROUP" -n "${AGENT_VM}-nsg" -o none --only-show-errors >/dev/null 2>&1 || true
  az network vnet delete -g "$RESOURCE_GROUP" -n "${AGENT_VM}-vnet" -o none --only-show-errors >/dev/null 2>&1 || true
}

step "Criando a VM do agente ($AGENT_VM)"
if [[ -n "$(az_out vm show -g "$RESOURCE_GROUP" -n "$AGENT_VM" --query id -o tsv 2>/dev/null || true)" ]]; then
  warn "A VM ja existe. Para recriar, apague-a antes: az vm delete -g $RESOURCE_GROUP -n $AGENT_VM --yes"
else
  ordered=("$RG_LOCATION")
  for r in "${REGIONS[@]}"; do [[ "$r" != "$RG_LOCATION" ]] && ordered+=("$r"); done
  CREATED=""
  for region in "${ordered[@]}"; do
    for size in "${VM_SIZES[@]}"; do
      avail=$(az_out vm list-skus -l "$region" --size "$size" --resource-type virtualMachines \
                --query "[?length(restrictions)==\`0\`].name" -o tsv 2>/dev/null || true)
      if [[ "$avail" != *"$size"* ]]; then echo "    $size indisponivel em $region"; continue; fi
      echo "    Tentando $size em $region (leva de 2 a 4 minutos)..."
      if out=$(az_out vm create -g "$RESOURCE_GROUP" -n "$AGENT_VM" -l "$region" --image "$VM_IMAGE" --size "$size" \
                 --admin-username azureuser --generate-ssh-keys --custom-data "$CLOUD_INIT" \
                 --vnet-name "${AGENT_VM}-vnet" --subnet agentes --nsg "${AGENT_VM}-nsg" --nsg-rule NONE \
                 --public-ip-address "${AGENT_VM}-ip" --public-ip-sku Standard \
                 -o none --only-show-errors 2>&1); then
        CREATED="$size em $region"; break 2
      fi
      warn "Falhou: $(resumo "$out")"
      cleanup_attempt
    done
  done
  rm -f "$CLOUD_INIT"
  [[ -n "$CREATED" ]] || fail "Nenhuma combinacao de tamanho/regiao funcionou. Mande a tela para a equipe."
  ok "VM criada: $CREATED"
fi

# --------------------- Aguarda o agente online -------------------
step "Aguardando o agente ficar Online no pool Default (ate 15 minutos)"
for i in $(seq 1 30); do
  st=$(curl -s -u ":$PAT" "$ORG_URL/_apis/distributedtask/pools/$POOL_ID/agents?agentName=$AGENT_NAME&api-version=7.1" | json_field status || true)
  if [[ "$st" == "online" ]]; then ok "Agente $AGENT_NAME online."; break; fi
  echo "    [$i/30] status: ${st:-instalando}..."
  sleep 30
done
[[ "${st:-}" == "online" ]] || fail "O agente nao ficou online. Veja na VM: sudo tail -n 100 /var/log/cloud-init-output.log"

echo
echo "Proximos passos:"
echo "  1. Troque o pool nos dois YAML e faca commit:"
echo "     sed -i 's/^  vmImage: ubuntu-24.04\$/  name: Default/' azure-pipelines-ci.yml azure-pipelines-cd.yml"
echo "  2. Revogue o PAT em User settings > Personal access tokens (o agente nao precisa mais dele)."
echo "  3. Para economizar creditos fora dos testes: az vm deallocate -g $RESOURCE_GROUP -n $AGENT_VM"
echo "     Antes de usar de novo:                    az vm start -g $RESOURCE_GROUP -n $AGENT_VM"
