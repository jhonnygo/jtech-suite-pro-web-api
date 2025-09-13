#!/usr/bin/env bash
# Instala y registra un self-hosted runner en el bastion
# Requiere: alias SSH "bastion-stage" en ~/.ssh/config funcionando.
# Vars necesarias: REPO_URL, RUNNER_TOKEN
# Vars opcionales: RUNNER_NAME, LABELS, VERSION, SSH_TARGET

# Ejemplo de uso:
#
# RUNNER_TOKEN='mi-token' SSH_TARGET='bastion-stage' ./01-register-gh-runner.sh

set -euo pipefail

: "${RUNNER_TOKEN:?Falta RUNNER_TOKEN (registration token de GitHub)}"

SSH_TARGET="${SSH_TARGET:-bastion-stage}"
RUNNER_NAME="${RUNNER_NAME:-bastion-stage-$(date +%Y%m%d-%H%M)}"
LABELS="${LABELS:-self-hosted,bastion-stage}"
VERSION="${VERSION:-2.328.0}"   # Version del paquete de runner en GitHub
REPO_URL="https://github.com/jhonnygo/jtech-suite-pro-web-api"

echo "[INFO] Registrando runner en ${SSH_TARGET} para ${REPO_URL}"
echo "[INFO] NAME=${RUNNER_NAME} LABELS=${LABELS} VERSION=${VERSION}"

ssh "${SSH_TARGET}" bash -s <<REMOTE
set -euo pipefail
sudo su

# 1) Desinstalar/limpiar si ya había un runner
systemctl stop "actions.runner.*" 2>/dev/null || true

if [ -d /home/gha/actions-runner ]; then
  cd /home/gha/actions-runner >/dev/null 2>&1
  ./svc.sh stop >/dev/null 2>&1
  ./svc.sh uninstall >/dev/null 2>&1
  rm -rf /home/gha/actions-runner >/dev/null 2>&1
fi
systemctl daemon-reload


# 2) Usuario dedicado (igual que hicimos a mano)
if ! id -u gha >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" gha
fi

# 3) Dependencias
apt-get update -y
apt-get install -y curl tar gzip ca-certificates git

# 4) Como 'gha': carpeta, descarga, descompresión y config (comandos "tal cual" del asistente de GitHub)
sudo -iu gha bash <<'EOSU'
set -euo pipefail
mkdir -p ~/actions-runner
cd ~/actions-runner
curl -L -o actions-runner-linux-x64-${VERSION}.tar.gz https://github.com/actions/runner/releases/download/v${VERSION}/actions-runner-linux-x64-${VERSION}.tar.gz
tar xzf actions-runner-linux-x64-${VERSION}.tar.gz
./config.sh \
  --url "${REPO_URL}" \
  --token "${RUNNER_TOKEN}" \
  --name "${RUNNER_NAME}" \
  --labels "${LABELS}" \
  --unattended --replace
EOSU

# 5) Instalar/arrancar como servicio (esto sí requiere root; se instala para el usuario 'gha')
cd /home/gha/actions-runner
./svc.sh install gha
./svc.sh start

# 6) Estado
systemctl is-active actions.runner.* && echo "[OK] Runner activo"
REMOTE

echo "[DONE] Ha finalizado el registro del Runner."
