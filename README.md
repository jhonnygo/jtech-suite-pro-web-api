# 🚀 CI/CD vía SSH — Stage (GitHub Actions + Runner en Bastion)

> **Objetivo**: desplegar la app `api` en **stage** vía SSH usando un **runner self‑hosted** instalado en el *bastion*.
>
> **Entorno**: **WSL** (cliente), **Ubuntu/Debian** en bastion y app.

---

## 📚 Índice
- [✅ Antes de empezar](#-antes-de-empezar)
- [🔐 Configurar SSH (`~/.ssh/config`)](#-configurar-ssh-sshconfig)
- [⚙️ Variables comunes](#️-variables-comunes)
- [▶️ Ejecutar los scripts (en orden)](#️-ejecutar-los-scripts-en-orden)
- [🧪 Verificación rápida](#-verificación-rápida)
- [ℹ️ Notas y personalización](#️-notas-y-personalización)
- [🧯 Troubleshooting rápido](#-troubleshooting-rápido)

> 💡 **Copiar con un clic**: en GitHub, cada bloque de código tiene un botón de **copiar**. En WSL/VS Code también suele aparecer. Si lo ves en texto plano, selecciona el bloque y copia.

---

## ✅ Antes de empezar

- [ ] Tienes **acceso SSH** al bastion (**IP pública**) y a la app (**IP privada**).
- [ ] Estás en la **raíz del repo** en tu WSL.

```bash
pwd
test -d .git && echo "OK: raíz del repo" || echo "❌ No estás en un repo Git"
```

---

## 🔐 Configurar SSH (`~/.ssh/config`)

> Define los alias para saltar por el bastion y llegar a la app (y opcionalmente a la DB).

```bash
nano ~/.ssh/config
```

```sshconfig
# Bastion (IP pública)
Host bastion-stage
  HostName     <IP_PUBLICA_BASTION>
  User         ubuntu
  IdentityFile ~/.ssh/<TU_PEM_O_OPENSSH>

# App (IP privada, salta por el bastion)
Host app-stage
  HostName     <IP_PRIVADA_APP>
  User         ubuntu
  ProxyJump    bastion-stage
  IdentityFile ~/.ssh/<TU_PEM_O_OPENSSH>

# (Opcional) Base de datos (IP privada, salta por el bastion)
Host db-stage
  HostName     <IP_PRIVADA_DB>
  User         ubuntu
  ProxyJump    bastion-stage
  IdentityFile ~/.ssh/<TU_PEM_O_OPENSSH>
```

**Campos a rellenar:**  
1. IP **pública** de bastion  
2. IP **privada** de app  
3. (Opcional) IP **privada** de db

> ✅ Prueba: `ssh app-stage` → debería conectar saltando por `bastion-stage`.

---

## ⚙️ Variables comunes

> Usa **SIEMPRE** estas dos (las demás tienen valores por defecto en los scripts).  
> El token lo obtienes en: **Settings → Actions → Runners → New self-hosted runner → Registration token**.

```bash
export RUNNER_TOKEN="AQUI_TU_TOKEN_DEL_RUNNER"
export APP_STAGE_IP="10.0.1.212"   # IP privada de la app-stage
export APP_PROD_IP="10.0.2.200"   # IP privada de la app-prod
```

---

## ▶️ Ejecutar los scripts (en orden)

> Ejecutar **desde la raíz del repo** en WSL. Todos son **locales**; algunos se conectan por SSH según tu `~/.ssh/config`.

```bash
# 1) Registrar (o re-registrar) el runner en el bastion
./scripts/01-register-gh-runner.sh

# 2) Preparar acceso de deploy (usuario 'deploy', clave autorizada, docroot y sudoers)
./scripts/02-setup-deploy-access-stage.sh

# 3) Generar el workflow de stage (solo escribe el YAML en tu repo local)
./scripts/03-generate-workflow-api-stage.sh

# 4) Generar el workflow de prod (solo escribe el YAML en tu repo local)
./scripts/04-generate-workflow-api-prod.sh
```

> 📄 El workflow se genera en:  
> `.github/workflows/deploy-workflow-api-stage.yml`
> `.github/workflows/deploy-workflow-api-prod.yml`

---

## 🧪 Verificación rápida

**Runner online**  
Repo → **Settings** → **Actions** → **Runners** → debería aparecer `bastion-stage` en **Idle**.

**Probar pipeline (branch `develop`)**

```bash
git add .
git commit -m "test: trigger deploy stage"
git push -u origin develop
```

En **Actions** verás el job **Deploy STAGE** ejecutándose en `[self-hosted, bastion-stage]`.

---

**Probar pipeline (branch `main`) haciendo un PULL REQUEST**

En **Actions** verás el job **Deploy STAGE** ejecutándose en `[self-hosted, bastion-stage]`.

---

## ℹ️ Notas y personalización

- El workflow empaqueta `www/api`, sube por `scp`, despliega en `/var/www/api` con `flock`, recarga Apache y hace **health‑check** a `${APP_URL}` (por defecto: `https://stage.yotkt.com/`).  
- Para otras apps (p. ej. `cv`, `store`), cambia `APP_DIR` en el YAML o genera workflows específicos.  
- Si rehaces la infra con Terraform, vuelve a ejecutar `01`, `02` y `03` y listo.

<details>
<summary><strong>¿Qué hace cada script?</strong></summary>

- **01-register-gh-runner.sh**: instala/actualiza el **runner** de GitHub en el bastion con la etiqueta `bastion-stage`.  
- **02-setup-deploy-access-stage.sh**: crea usuario `deploy` en la app, autoriza la clave generada en bastion, deja `/var/www/api` y permisos/sudoers.  
- **03-generate-workflow-stage.sh**: genera el YAML del workflow (no ejecuta nada remoto).
</details>

---

## 🧯 Troubleshooting rápido

**`Permission denied (publickey)` al scp/ssh desde el workflow**  
- Asegúrate de que la pública de `gha@app-stage-deploy` está en `/home/deploy/.ssh/authorized_keys` de la app.  
- Permisos correctos:  
  ```bash
  ssh app-stage 'ls -ld /home/deploy/.ssh && ls -l /home/deploy/.ssh/authorized_keys'
  # .ssh => 700 ; authorized_keys => 600 ; owner deploy:deploy
  ```

**Runner no toma el job (queda “Waiting for a runner…”)**  
- Revisa en bastion:  
  ```bash
  ssh bastion-stage 'systemctl status "actions.runner.*" || ls -l /home/gha/actions-runner'
  ```

**Health-check falla**  
- Comprueba que la URL de stage responde (`200` o `204`):  
  ```bash
  curl -I https://stage.yotkt.com/
  ```
