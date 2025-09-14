#!/usr/bin/env bash
set -euo pipefail

# ===== Parámetros (con defaults) =====
# Usamos tu APP_PROD_IP si está exportada (p.ej. APP_PROD_IP=10.0.1.212).
APP_DIR="${APP_DIR:-api}"
RUNNER_LABEL="${RUNNER_LABEL:-bastion-prod}"
APP_URL_PROD="${APP_URL_PROD:-https://yotkt.com/}"
APP_HOST_PROD="${APP_HOST_PROD:-${APP_PROD_IP:-APP_PROD_HOST_PLACEHOLDER}}"
REMOTE_USER="${REMOTE_USER:-deploy}"
SSH_KEY_PATH="${SSH_KEY_PATH:-/home/gha/.ssh/app-deploy}"

WF=".github/workflows/deploy-workflow-api-prod.yml"
mkdir -p .github/workflows

# Plantilla con placeholders (no se expanden aquí)
cat > "$WF" <<'YAML'
name: Deploy via SSH (PROD)

on:
  push:
    branches: [ main ]

jobs:
  deploy_prod:
    name: Deploy PROD (bastion-prod → app-prod)
    runs-on: [ self-hosted, RUNNER_LABEL_PLACEHOLDER ]
    env:
      APP_DIR: APP_DIR_PLACEHOLDER
      APP_URL: APP_URL_PROD_PLACEHOLDER
      APP_HOST: APP_HOST_PROD_PLACEHOLDER
      REMOTE_USER: REMOTE_USER_PLACEHOLDER
      SSH_KEY_PATH: SSH_KEY_PATH_PLACEHOLDER
      PKG_BASENAME: api-${{ github.sha }}.tar.gz
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Empaquetar release (tar.gz + .env)
        run: |
          set -euo pipefail
          mkdir -p build
          cp -a "www/$APP_DIR/." build/
          if [ -d scripts ]; then cp -a scripts build/; fi
          printf 'APP_DIR=%s\nAPP_URL=%s\n' "$APP_DIR" "$APP_URL" > build/.env
          tar -C build -czf "/tmp/$PKG_BASENAME" .
          ls -lh "/tmp/$PKG_BASENAME"

      - name: Subir paquete a la app (scp)
        run: |
          set -euo pipefail
          scp -o StrictHostKeyChecking=accept-new -i "$SSH_KEY_PATH" \
            "/tmp/$PKG_BASENAME" "$REMOTE_USER@$APP_HOST:/tmp/"

      - name: Desplegar en remoto (flock + copiar + permisos + reload Apache)
        run: |
          set -euo pipefail
          ssh -o StrictHostKeyChecking=accept-new -i "$SSH_KEY_PATH" \
            "$REMOTE_USER@$APP_HOST" "PKG_BASENAME=$PKG_BASENAME bash -s" <<'EOSH'
          set -euo pipefail
          DOCROOT="/var/www/APP_DIR_PLACEHOLDER"
          PKG="/tmp/${PKG_BASENAME}"
          LOCK="${DOCROOT}/.deploy.lock"

          flock -w 300 "$LOCK" bash -c '
            set -euo pipefail
            TMPD=$(mktemp -d)
            tar -xzf "'"$PKG"'" -C "$TMPD"
            # Limpiar docroot (incluye archivos ocultos)
            find "'"$DOCROOT"'" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
            # Copiar nuevos archivos
            cp -a "$TMPD"/. "'"$DOCROOT"'"/
            # Permisos consistentes
            find "'"$DOCROOT"'" -type d -exec chmod 2775 {} \;
            find "'"$DOCROOT"'" -type f -exec chmod 664 {} \;
            rm -rf "$TMPD" "'"$PKG"'"
          '
          # Recargar Apache (permitido por sudoers del usuario deploy)
          sudo systemctl reload apache2
          EOSH

      - name: Health-check (URL pública de prod)
        run: |
          set -euo pipefail
          URL="${APP_URL%/}/"
          echo "Health-check: $URL"
          for i in {1..10}; do
            CODE=$(curl -ks -o /dev/null -w '%{http_code}' "$URL" || true)
            echo "Intento $i -> código $CODE"
            if [ "$CODE" = "200" ] || [ "$CODE" = "204" ]; then
              exit 0
            fi
            sleep 2
          done
          echo "ERROR: health-check falló en $URL"
          exit 1
YAML

# Sustituimos placeholders por los valores (APP_HOST_PROD usa APP_PROD_IP si estaba exportada)
sed -i \
  -e "s|RUNNER_LABEL_PLACEHOLDER|${RUNNER_LABEL}|g" \
  -e "s|APP_DIR_PLACEHOLDER|${APP_DIR}|g" \
  -e "s|APP_URL_PROD_PLACEHOLDER|${APP_URL_PROD}|g" \
  -e "s|APP_HOST_PROD_PLACEHOLDER|${APP_HOST_PROD}|g" \
  -e "s|REMOTE_USER_PLACEHOLDER|${REMOTE_USER}|g" \
  -e "s|SSH_KEY_PATH_PLACEHOLDER|${SSH_KEY_PATH}|g" \
  "$WF"

echo "[OK] Generado $WF con:"
echo "     - Runner label : ${RUNNER_LABEL}"
echo "     - APP_DIR      : ${APP_DIR}"
echo "     - APP_URL      : ${APP_URL_PROD}"
echo "     - APP_HOST     : ${APP_HOST_PROD}"
echo "     - REMOTE_USER  : ${REMOTE_USER}"
echo "     - SSH_KEY_PATH : ${SSH_KEY_PATH}"
