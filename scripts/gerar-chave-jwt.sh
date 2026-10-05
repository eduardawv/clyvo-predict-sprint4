#!/usr/bin/env bash
# =================================================================
# CLYVO Predict - Sprint 4 - Gera o par de chaves RSA do JWT
#
# - Chave PRIVADA: .keys/private_key.pem  (ignorada pelo git)
#   -> enviar para Azure DevOps > Pipelines > Library > Secure files
#      com o nome private_key.pem (o CI baixa de la a cada build)
# - Chave PUBLICA: src/main/resources/keys/public_key.pem (vai para o git)
#
# Uso (Git Bash, na raiz do repositorio):  bash scripts/gerar-chave-jwt.sh
# Rodar UMA vez, antes do primeiro commit. Rodar de novo reaproveita a
# chave privada existente (nao troca as chaves).
# =================================================================
set -Eeuo pipefail
# shellcheck source=scripts/config.sh
source "$(dirname "$0")/config.sh"

KEY_DIR=".keys"
PRIVATE_KEY="$KEY_DIR/private_key.pem"
PUBLIC_KEY="src/main/resources/keys/public_key.pem"

[[ -f pom.xml && -d src/main/resources ]] || fail "Execute na raiz do repositorio (pasta onde esta o pom.xml)."
command -v openssl >/dev/null 2>&1 || fail "openssl nao encontrado (ele vem com o Git Bash)."
git check-ignore -q "$PRIVATE_KEY" 2>/dev/null || [[ ! -d .git ]] || fail ".keys/ nao esta no .gitignore. Nao continue: a chave privada iria para o GitHub."

mkdir -p "$KEY_DIR" "$(dirname "$PUBLIC_KEY")"
if [[ -s "$PRIVATE_KEY" ]]; then
  ok "Chave privada ja existe em $PRIVATE_KEY (reaproveitada)."
else
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$PRIVATE_KEY" 2>/dev/null
  ok "Chave privada gerada em $PRIVATE_KEY"
fi
openssl pkey -in "$PRIVATE_KEY" -pubout -out "$PUBLIC_KEY" 2>/dev/null
ok "Chave publica gravada em $PUBLIC_KEY"

echo
echo "Proximos passos:"
echo "  1. Commit da chave publica (ela vai para o GitHub)."
echo "  2. Azure DevOps > Pipelines > Library > Secure files > + Secure file:"
echo "     envie o arquivo $(pwd -W 2>/dev/null || pwd)/$PRIVATE_KEY"
echo "     (o nome no Azure DevOps tem que ser exatamente private_key.pem)"
echo "  3. NUNCA faca commit da pasta .keys/"
