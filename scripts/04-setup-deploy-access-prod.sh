#!/usr/bin/env bash
# Prepara el acceso de deploy para prod funcionando todo como root en remoto.

set -euo pipefail

# --- Defaults locales ---
SSH_BASTION="${SSH_BASTION:-bastion-prod}"
SSH_APP="${SSH_APP:-app-prod}"
DEPLOY_USER="${DEPLOY_USER:-deploy}"
KEY_NAME="${KEY_NAME:-app-deploy}"
DOCROOT="${DOCROOT:-/var/www/api}"
APACHE_SUDOERS="${APACHE_SUDOERS:-/etc/sudoers.d/99-deploy-apache}"
APP_PROD_IP="${APP_PROD_IP:-}"   # opcional (para sembrar known_hosts)

echo "[1/4] Reset ~/.ssh en bastion (${SSH_BASTION}) y generación de clave nueva (${KEY_NAME})"
ssh "${SSH_BASTION}" "KEY_NAME='${KEY_NAME}' APP_PROD_IP='${APP_PROD_IP}' sudo -s bash -s" <<'BASTION_ROOT'
set -euo pipefail
: "${KEY_NAME:=app-deploy}"
: "${APP_PROD_IP:=}"

# Asegurar usuario gha
id -u gha >/dev/null 2>&1 || adduser --disabled-password --gecos "" gha

# Reset TOTAL de ~/.ssh (sin prompts)
rm -rf /home/gha/.ssh
install -d -m 700 -o gha -g gha /home/gha/.ssh

# Generar clave como gha (sin prompts)
su -s /bin/bash -c "ssh-keygen -q -t ed25519 -N '' -C 'gha@${KEY_NAME}' -f /home/gha/.ssh/${KEY_NAME}" gha

# (Opcional) known_hosts para la IP privada de la app
if [ -n "${APP_PROD_IP}" ]; then
  su -s /bin/bash -c "ssh-keyscan -H ${APP_PROD_IP} >> /home/gha/.ssh/known_hosts && chmod 600 /home/gha/.ssh/known_hosts" gha
fi

chmod 600 /home/gha/.ssh/${KEY_NAME} /home/gha/.ssh/${KEY_NAME}.pub
chown -R gha:gha /home/gha/.ssh
echo "[OK] Clave creada: /home/gha/.ssh/${KEY_NAME}"
BASTION_ROOT

echo "[2/4] Leyendo clave pública del bastion"
PUB_B64="$(ssh "${SSH_BASTION}" "sudo base64 -w0 /home/gha/.ssh/${KEY_NAME}.pub")"

echo "[3/4] Configurando ${DEPLOY_USER} y autorizando clave en app (${SSH_APP})"
ssh "${SSH_APP}" "sudo -s bash -s" <<APP_ROOT
set -euo pipefail
# Pasa los valores *literalmente* al remoto:
DEPLOY_USER="${DEPLOY_USER}"
DOCROOT="${DOCROOT}"
APACHE_SUDOERS="${APACHE_SUDOERS}"
# PUB_B64 puede llevar + / = ; envíalo como literal entre comillas simples:
PUB_B64='${PUB_B64}'

: "\${PUB_B64:?Falta PUB_B64}"

# Usuario deploy
id -u "\$DEPLOY_USER" >/dev/null 2>&1 || adduser --disabled-password --gecos "" "\$DEPLOY_USER"
usermod -aG www-data "\$DEPLOY_USER" || true
passwd -l "\$DEPLOY_USER" >/dev/null 2>&1 || true

# .ssh y authorized_keys
install -d -m 700 -o "\$DEPLOY_USER" -g "\$DEPLOY_USER" "/home/\$DEPLOY_USER/.ssh"
install -m 600 -o "\$DEPLOY_USER" -g "\$DEPLOY_USER" /dev/null "/home/\$DEPLOY_USER/.ssh/authorized_keys"

# Añadir la pública (evita duplicados)
PUB="\$(echo "\$PUB_B64" | base64 -d)"
grep -Fqx "\$PUB" "/home/\$DEPLOY_USER/.ssh/authorized_keys" || echo "\$PUB" >> "/home/\$DEPLOY_USER/.ssh/authorized_keys"
chown "\$DEPLOY_USER:\$DEPLOY_USER" "/home/\$DEPLOY_USER/.ssh/authorized_keys"
chmod 600 "/home/\$DEPLOY_USER/.ssh/authorized_keys"

# Sudoers mínimo (Apache)
if [ ! -f "\$APACHE_SUDOERS" ]; then
  cat >"\$APACHE_SUDOERS" <<EOF
Cmnd_Alias APACHE_CMDS = /bin/systemctl reload apache2, /bin/systemctl restart apache2, /usr/bin/systemctl reload apache2, /usr/bin/systemctl restart apache2
\${DEPLOY_USER} ALL=(root) NOPASSWD: APACHE_CMDS
EOF
  chmod 440 "\$APACHE_SUDOERS"
  visudo -cf /etc/sudoers >/dev/null
fi

# Docroot + permisos
install -d -m 2775 -o "\$DEPLOY_USER" -g www-data "\$DOCROOT"
chown -R "\$DEPLOY_USER":www-data "\$DOCROOT"
find "\$DOCROOT" -type d -exec chmod 2775 {} \;
find "\$DOCROOT" -type f -exec chmod 664 {} \;

# Umask colaborativa
grep -q '^umask 002' "/home/\$DEPLOY_USER/.profile" 2>/dev/null || echo 'umask 002' >> "/home/\$DEPLOY_USER/.profile"
grep -q '^umask 002' "/home/\$DEPLOY_USER/.bashrc"   2>/dev/null || echo 'umask 002' >> "/home/\$DEPLOY_USER/.bashrc"

echo "[OK] \$DEPLOY_USER listo y clave autorizada"
APP_ROOT

# (4/4) (ya sembrado en paso 1 si pasaste APP_PROD_IP)
[ -n "${APP_PROD_IP}" ] && echo "[4/4] known_hosts se sembró en paso 1" || echo "[4/4] (opcional) APP_PROD_IP no definido; me salto known_hosts"

echo "[DONE] Acceso gha(bastion) → ${DEPLOY_USER}(app-prod) listo."
