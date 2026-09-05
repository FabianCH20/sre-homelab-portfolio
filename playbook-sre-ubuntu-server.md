# Playbook SRE: Servidor Ubuntu desde Cero
🇬🇧 [Read in English](playbook-sre-ubuntu-server-eng.md)
> Formato: `comando → qué hace → por qué / síntoma que resuelve`
> Nivel: Junior SRE. Ejecutar en orden. Cada fase asume la anterior completa.

---

## FASE 1 — Hardening base del sistema

**Referencias oficiales:**
- [Ubuntu Server: Security](https://documentation.ubuntu.com/server/how-to/security/) — guía oficial de hardening de Ubuntu Server
- [UFW — Ubuntu Wiki oficial](https://help.ubuntu.com/community/UFW) · [Fail2ban Docs](https://fail2ban.readthedocs.io/)
- [github.com/fail2ban/fail2ban](https://github.com/fail2ban/fail2ban) — repositorio del proyecto Fail2ban

```bash
sudo apt update && sudo apt upgrade -y
```
→ `update` refresca índice de paquetes, `upgrade` instala versiones nuevas. **Síntoma que resuelve**: CVEs conocidos sin parchear.

```bash
sudo apt install -y ufw fail2ban unattended-upgrades curl wget git htop vim net-tools
```
→ Herramientas base: `ufw` (firewall simple), `fail2ban` (bloquea IPs por fuerza bruta), `unattended-upgrades` (parches de seguridad automáticos).

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 2222/tcp
sudo ufw enable
```
→ Firewall en modo "todo cerrado excepto lo explícito". **Fix**: si usas otro puerto SSH, ábrelo ANTES de `enable`.

```bash
sudo systemctl enable fail2ban --now
sudo fail2ban-client status sshd
```
→ Activa y verifica protección contra brute-force SSH.

```bash
sudo timedatectl set-timezone America/Costa_Rica
sudo timedatectl set-ntp true
```
→ Hora sincronizada es crítica: logs desalineados = debugging imposible, certificados TLS fallan con drift.

```bash
sudo hostnamectl set-hostname srv-prod-01
```
→ Nombra el host de forma consistente con tu inventario (útil luego en Ansible).

---

## FASE 2 — Bash: fundamentos operativos

**Referencias oficiales:**
- [GNU Bash Reference Manual](https://www.gnu.org/software/bash/manual/bash.html) — documentación oficial de Bash
- [github.com/koalaman/shellcheck](https://github.com/koalaman/shellcheck) — linter estático de shell scripts, con [wiki de reglas](https://github.com/koalaman/shellcheck/wiki) que documenta errores comunes (recomendado correr sobre cualquier script antes de producción)

### 2.1 — Crear el archivo

```bash
mkdir -p /opt/scripts
cd /opt/scripts
nano backup.sh
```
→ `mkdir -p`: crea el directorio si no existe (`-p` = no falla si ya existe, y crea padres intermedios). Convención en ops: guardar scripts propios en `/opt/scripts`, no en `/home` ni en `/tmp` (se pierde en reboot en algunos setups). `nano` es el editor; puedes usar `vim` si lo prefieres.

Escribe esto dentro de `nano`:
```bash
#!/usr/bin/env bash
echo "Hola, soy un script"
```
→ Guardar en nano: `Ctrl+O` (write out) → `Enter` → `Ctrl+X` (salir).

**¿Qué es la primera línea?**
```bash
#!/usr/bin/env bash
```
→ Se llama **shebang**. Le dice al sistema operativo con qué intérprete ejecutar el archivo. Sin esta línea, el sistema no sabe si es bash, python, etc., y trata el archivo como texto plano. `env bash` (en vez de `/bin/bash` fijo) busca bash en el `PATH` del sistema — más portable entre distros.

### 2.2 — Dar permisos de ejecución

```bash
ls -l backup.sh
```
→ Verás algo como `-rw-r--r--`. Esos primeros 10 caracteres son permisos: el archivo NO tiene permiso de ejecución (no hay `x`).

```bash
chmod +x backup.sh
ls -l backup.sh
```
→ `chmod +x` agrega permiso de ejecución. Ahora verás `-rwxr--r--` (la `x` apareció). **Síntoma que resuelve**: error `Permission denied` al intentar correr el script.

Desglose de permisos `-rwxr--r--`:
```
- rwx r-- r--
| |   |   └─ otros: solo lectura
| |   └───── grupo: solo lectura
| └───────── dueño: lectura, escritura, ejecución
└─────────── tipo de archivo (- = archivo normal, d = directorio)
```

### 2.3 — Ejecutar el script

```bash
./backup.sh
```
→ El `./` es obligatorio si el directorio actual no está en tu `PATH` (normalmente no lo está, por seguridad — evita que un archivo malicioso llamado `ls` en tu carpeta actual se ejecute en vez del `ls` real del sistema).

```bash
bash backup.sh
```
→ Alternativa que **no requiere** `chmod +x`, porque le estás diciendo explícitamente a bash que lo interprete. Útil para pruebas rápidas, pero en producción usa `./script.sh` con permisos correctos y shebang — es el estándar.

### 2.4 — Variables y argumentos

```bash
#!/usr/bin/env bash
NOMBRE="servidor-01"
echo "Backup de: $NOMBRE"
```
→ Variables sin espacios alrededor del `=` (`NOMBRE = "x"` es un error común de sintaxis). Se leen con `$NOMBRE` o `${NOMBRE}`.

```bash
#!/usr/bin/env bash
echo "Script ejecutado: $0"
echo "Primer argumento: $1"
echo "Total de argumentos: $#"
```
```bash
./backup.sh produccion
```
→ `$0` = nombre del script, `$1` = primer argumento pasado (`produccion`), `$#` = cantidad de argumentos. Así los scripts reciben parámetros en vez de tener valores fijos ("hardcoded").

### 2.5 — Condicionales y control de flujo

```bash
#!/usr/bin/env bash
if [ -d "/var/backups" ]; then
  echo "El directorio existe"
else
  mkdir -p /var/backups
  echo "Directorio creado"
fi
```
→ `-d` prueba si es un directorio existente. Otros comunes: `-f` (archivo existe), `-z` (string vacío), `-eq`/`-gt`/`-lt` (comparación numérica). **Ojo**: los espacios dentro de `[ ]` son obligatorios (`[-d "/ruta"]` sin espacios da error).

### 2.6 — Funciones

```bash
#!/usr/bin/env bash
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Iniciando backup"
tar -czf /var/backups/backup.tar.gz /etc/nginx
log "Backup completado"
```
→ Funciones evitan repetir código. `$(date ...)` es "command substitution": ejecuta `date` y sustituye su salida ahí mismo. Este patrón de `log()` con timestamp es el mínimo que todo script de producción debería tener.

### 2.7 — Cabecera obligatoria de producción

Ahora que entiendes las piezas sueltas, esta es la cabecera que **todo script de ops debe llevar**, y por qué:

```bash
#!/usr/bin/env bash
set -euo pipefail
```
→ Cabecera obligatoria en TODO script de ops:
- `set -e`: aborta si un comando falla (evita que el script siga "a ciegas")
- `set -u`: error si usas variable no definida
- `set -o pipefail`: detecta fallos dentro de pipes (`cmd1 | cmd2`)

```bash
LOGFILE="/var/log/miapp/deploy.log"
exec > >(tee -a "$LOGFILE") 2>&1
```
→ Redirige stdout+stderr a log y pantalla simultáneamente. **Por qué**: sin esto, si el proceso truena a las 3am no tienes evidencia.

```bash
if ! systemctl is-active --quiet nginx; then
  echo "ERROR: nginx caído" >&2
  systemctl restart nginx
fi
```
→ Patrón check-then-fix. `is-active --quiet` no imprime nada, solo devuelve exit code (0=activo).

```bash
find /var/log -name "*.log" -mtime +30 -exec gzip {} \;
```
→ Comprime logs con más de 30 días. **Síntoma que resuelve**: disco lleno por logs sin rotar.

```bash
df -h | awk '$5+0 > 80 {print $0}'
```
→ Filtra particiones con más de 80% uso. `$5+0` fuerza conversión numérica del `%`.

```bash
journalctl -u nginx.service --since "1 hour ago" -p err
```
→ Logs de systemd filtrados por servicio, tiempo y prioridad (error). Reemplaza `tail -f /var/log/*` obsoleto.

### 2.8 — Bitácora de incidentes

Los errores reales encontrados practicando esta fase (permisos en `/opt`, sintaxis de `if`/`fi`, `tar` fallando en silencio, `sh` vs `bash`, espacios en `process substitution`, permisos en `/var/log`) quedaron documentados por separado en **[incidentes-sre.md](./incidentes-sre.md)**, sección "FASE 2 — Bash". Vale la pena tenerlos en un archivo aparte: así puedes seguir agregando incidentes según sigas practicando, sin que el playbook principal crezca indefinidamente — y en tu repo de GitHub, es justo el tipo de evidencia de troubleshooting que un evaluador de portfolio valora ver como archivo propio.

---

## FASE 3 — Python para automatización

**Referencias oficiales:**
- [docs.python.org/3](https://docs.python.org/3/) — documentación oficial de Python
- [PEP 668 — Marking Python base environments as "externally managed"](https://peps.python.org/pep-0668/) — spec detrás del error `externally-managed-environment`
- [github.com/python/cpython](https://github.com/python/cpython) · [github.com/pypa/pip](https://github.com/pypa/pip)
- [crontab(5) — Linux man-pages](https://man7.org/linux/man-pages/man5/crontab.5.html) — referencia oficial del formato cron

```bash
sudo apt install -y python3-pip python3-venv
python3 -m venv /opt/venvs/ops
source /opt/venvs/ops/bin/activate
```
→ **Nunca** `pip install` a nivel de sistema en Ubuntu moderno (rompe apt). Siempre entornos virtuales aislados.

**Fix si sale `source: command not found`**

Este es el mismo patrón que el Incidente #4 de la bitácora (bash vs `sh`/`dash`): `source` es un comando **interno de bash**, no existe en `sh` (que en Ubuntu es `dash`, un shell más limitado). Si ves este error, tu sesión actual está corriendo en `sh`, no en `bash`.

**Diagnóstico:**
```bash
echo $0
```
→ Si muestra `sh` o `dash` (en vez de `bash` o `-bash`), confirmado.

**Fix — dos opciones:**

**Opción 1**: usa `.` (un solo punto) en vez de `source` — es el equivalente POSIX, funciona en cualquier shell, incluido `sh`:
```bash
. /opt/venvs/ops/bin/activate
```

**Opción 2**: cambia a bash antes de continuar:
```bash
bash
source /opt/venvs/ops/bin/activate
```
→ Esto abre una sesión de bash dentro de tu sesión actual, donde `source` sí existe.

**Verifica que el venv quedó activo** (cualquiera de las dos opciones):
```bash
which python
```
→ Debe mostrar `/opt/venvs/ops/bin/python`, no la ruta del sistema.

```python
# healthcheck.py
import requests
import sys
import logging

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

def check_endpoint(url: str, timeout: int = 5) -> bool:
    try:
        r = requests.get(url, timeout=timeout)
        r.raise_for_status()
        return True
    except requests.RequestException as e:
        logging.error(f"Fallo en {url}: {e}")
        return False

if __name__ == "__main__":
    ok = check_endpoint("http://localhost:8080/health")
    sys.exit(0 if ok else 1)
```
→ Script de healthcheck básico. **Por qué Python y no bash aquí**: manejo de errores estructurado, parsing JSON, reutilizable como librería.

```bash
pip install requests
pip freeze > requirements.txt
```
→ `freeze` congela versiones exactas. **Síntoma que evita**: "en mi máquina funciona" por drift de dependencias.

### 3.0.1 — Crontab paso a paso: agregar, verificar y ver ejecución en tiempo real

**1. Abrir el crontab de tu usuario**

```bash
crontab -e
```
→ Abre el archivo de tareas programadas de tu usuario actual (no de root, a menos que uses `sudo crontab -e`). La **primera vez** que lo ejecutas, te preguntará qué editor usar:
```
no crontab for opsuser - using an empty one

Select an editor.
  1. /bin/nano
  2. /usr/bin/vim
```
→ Elige `1` (nano) si no estás familiarizado con vim — es más simple para editar y guardar.

**2. Entender la estructura vacía**

Verás un archivo casi vacío con solo comentarios explicativos (líneas que empiezan con `#`, que cron ignora). Al final, agrega tu línea:

```
*/5 * * * * /opt/venvs/ops/bin/python /opt/scripts/healthcheck.py >> /var/log/healthcheck-cron.log 2>&1
```

Desglose de los 5 primeros campos (el formato cron):
```
*/5 *  *  *  *
│   │  │  │  │
│   │  │  │  └── día de la semana (0-7, domingo=0 o 7)
│   │  │  └───── mes (1-12)
│   │  └──────── día del mes (1-31)
│   └─────────── hora (0-23)
└─────────────── minuto (0-59)
```
→ `*/5 * * * *` = "cada 5 minutos, todos los días, todas las horas". El `*` solo significa "cualquier valor"; `*/5` significa "cada 5 unidades".

**3. Guardar y salir**

En nano: `Ctrl+O` → `Enter` (confirma nombre de archivo temporal) → `Ctrl+X` (salir).

Verás un mensaje de confirmación:
```
crontab: installing new crontab
```
→ Esto confirma que cron aceptó la sintaxis y la instaló. Si hubiera un error de formato grave, cron te lo hubiera señalado aquí.

**4. Verificar que quedó guardado**

```bash
crontab -l
```
→ `-l` (list) imprime el crontab actual sin abrir el editor. Debe mostrarte exactamente la línea que agregaste. **Este es tu primer punto de verificación** — si no aparece, no se guardó.

**5. Preparar el archivo de log ANTES de esperar**

```bash
sudo touch /var/log/healthcheck-cron.log
sudo chown $USER:$USER /var/log/healthcheck-cron.log
```
→ Igual que en incidentes anteriores: si el archivo no existe o no es tuyo, cron fallará silenciosamente al intentar escribir el log.

**6. Ver la ejecución en tiempo real**

Aquí es donde realmente "ves" que cron está funcionando. Abre una terminal y deja corriendo:

```bash
tail -f /var/log/healthcheck-cron.log
```
→ `-f` (follow) mantiene el archivo abierto y muestra nuevas líneas a medida que se escriben — no tienes que estar re-ejecutando el comando. Déjalo corriendo y espera al siguiente múltiplo de 5 minutos (ej. si son las 10:32, esperas hasta las 10:35).

Cuando cron dispare la tarea, verás aparecer en vivo algo como:
```
2026-08-26 10:35:01 INFO Healthcheck OK
```
o, si el endpoint no responde:
```
2026-08-26 10:35:01 ERROR Fallo en http://localhost:8080/health: Connection refused
```
→ Esa salida es exactamente el `logging.info`/`logging.error` que definiste dentro de `healthcheck.py` — cron simplemente está invocando tu script y redirigiendo su output ahí gracias al `>> ... 2>&1` que agregaste.

**7. Confirmar en paralelo que cron realmente disparó la tarea (no solo tu script)**

En otra terminal, mientras esperas:
```bash
grep CRON /var/log/syslog | tail -5
```
→ Verás una línea como:
```
CRON[12345]: (opsuser) CMD (/opt/venvs/ops/bin/python /opt/scripts/healthcheck.py >> /var/log/healthcheck-cron.log 2>&1)
```
→ Esto confirma, a nivel de sistema, que cron leyó tu crontab y ejecutó el comando exacto — independiente de si tu script tuvo éxito o no. Es tu prueba de que "cron sí corrió" separada de "el script sí funcionó".

**8. Verificar el exit code de la última ejecución (opcional, para debugging)**

Si quieres confirmar programáticamente si el healthcheck pasó o falló, recuerda que `sys.exit(0 if ok else 1)` en el script deja ese código disponible — pero cron no te lo muestra directamente. Para verlo necesitarías capturarlo dentro del propio comando:
```
*/5 * * * * /opt/venvs/ops/bin/python /opt/scripts/healthcheck.py >> /var/log/healthcheck-cron.log 2>&1; echo "Exit code: $?" >> /var/log/healthcheck-cron.log
```
→ Agrega el código de salida al mismo log, para saber sin ambigüedad si cada corrida fue éxito (`0`) o falla (`1`).

---

### 3.0.2 — Referencia rápida del comando original

```bash
crontab -e
```
```
*/5 * * * * /opt/venvs/ops/bin/python /opt/scripts/healthcheck.py
```
→ Ejecuta el check cada 5 min. **Fix común**: cron usa PATH mínimo — siempre rutas absolutas.

### 3.1 — Bitácora de incidentes

Los errores de esta fase (typos de sintaxis en `def`/`if __name__`, `pip` fuera del venv, permisos del venv, cronjob roto en el archivo `.cron`) están documentados en **[incidentes-sre.md](./incidentes-sre.md)**, sección "FASE 3 — Python".

---

## FASE 4 — Docker

**Referencias oficiales:**
- [docs.docker.com](https://docs.docker.com/) — documentación oficial de Docker Engine y Docker Compose
- [github.com/moby/moby](https://github.com/moby/moby) — repositorio del motor de Docker (Docker Engine)
- [github.com/docker/compose](https://github.com/docker/compose) — repositorio de Docker Compose
- [hub.docker.com](https://hub.docker.com/) — registro oficial de imágenes públicas (nginx, mysql, mariadb, wordpress, etc.)

> **Nota de contexto**: este es un **laboratorio de pruebas (lab)** para practicar — no un servidor de producción real. Por eso la instalación se hizo con el script oficial de un solo comando (más rápido para levantar el entorno una y otra vez mientras se aprende), en vez del proceso manual paso a paso que se usaría típicamente para documentar o auditar cada paso en un entorno productivo.

### 4.0 — Instalación: script oficial `get-docker.sh`

Docker ofrece un script de instalación de un solo comando que agrega la llave GPG, registra el repositorio oficial, e instala Docker Engine + Compose automáticamente. Este fue el método usado para este servidor de práctica.

**1. Descarga el script (sin ejecutarlo todavía)**

```bash
curl -fsSL https://get.docker.com -o get-docker.sh
```
→ A diferencia de `curl ... | sh` (que ejecuta el script a ciegas mientras se descarga), usar `-o get-docker.sh` lo guarda como archivo local primero. **Buena práctica de seguridad**: nunca ejecutes con `sudo` un script bajado de internet sin poder revisarlo antes.

**2. (Recomendado) Inspecciona el script antes de correrlo**

```bash
less get-docker.sh
```
→ Te permite leer qué hace el script (agregar repos, instalar paquetes, etc.) antes de darle privilegios de root. Sal de `less` con `q`.

**3. Ejecuta primero en modo de prueba (`--dry-run`)**

```bash
sudo sh ./get-docker.sh --dry-run
```
→ `--dry-run` hace que el script **muestre** qué comandos ejecutaría (agregar repo, instalar paquetes, etc.) **sin aplicarlos de verdad**. Es el equivalente al `docker compose config` o al `ansible-playbook --check` que ya viste en otras fases: valida el plan antes de comprometerte a ejecutarlo.

**4. Ejecuta la instalación real (quitando `--dry-run`)**

```bash
sudo sh ./get-docker.sh
```
→ Ahora sí instala Docker Engine, CLI, `containerd`, y los plugins de buildx y compose, todo en un solo paso automatizado.

**Verifica que el repo quedó registrado (útil si algo falla más adelante):**
```bash
ls /etc/apt/sources.list.d/docker.*
```
→ Debe mostrar `docker.list` o `docker.sources` (el script elige el formato según tu versión de Ubuntu). Si en algún momento ves los dos apuntando al mismo repo, elimina uno de los dos para evitar duplicados.

**5. Agrega tu usuario al grupo `docker`**

```bash
sudo usermod -aG docker krikox
```
→ Agrega específicamente al usuario `krikox` (el usuario real de trabajo en este servidor, confirmado con `whoami` en incidentes anteriores) al grupo `docker`.

```bash
exit
```
Y vuelve a conectarte — recuerda que `newgrp` no siempre basta después de un `usermod` (Incidente #12 de la bitácora).

**6. Verifica que quedó funcionando**

```bash
groups
docker run hello-world
docker compose version
```

**7. Prueba adicional con una imagen real: nginx**

Para confirmar que el ciclo completo de contenedores funciona más allá de `hello-world` (que solo imprime texto y termina), se descargó y corrió una imagen de servidor web real:

```bash
docker pull nginx
```
→ Descarga la imagen oficial de nginx desde Docker Hub, sin correrla todavía.

```bash
docker run -d --name nginx-test -p 8081:80 nginx
```
→ La levanta en segundo plano (`-d`), mapeando el puerto 8081 de tu servidor al puerto 80 dentro del contenedor (donde nginx escucha por defecto).

**Verifica que responde:**
```bash
curl http://localhost:8081
```
→ Debe devolver el HTML de bienvenida de nginx (`<h1>Welcome to nginx!</h1>` dentro del cuerpo). Esto confirma networking de contenedores funcionando de punta a punta — no solo que Docker corre un proceso, sino que expone puertos correctamente al host.

```bash
docker ps
```
→ Debe mostrar `nginx-test` con estado `Up` y el mapeo de puerto `0.0.0.0:8081->80/tcp`.

---

### 4.1 — Referencia rápida (una vez que ya está instalado)

```bash
docker run hello-world
```
→ Descarga (si no la tienes localmente) y ejecuta la imagen oficial de prueba `hello-world`. Verás una salida de texto explicando qué acaba de pasar internamente. **Qué confirma exactamente**:
1. El cliente Docker (`docker`) pudo hablar con el daemon Docker (`dockerd`) — confirma que el servicio está corriendo.
2. El daemon pudo descargar la imagen desde Docker Hub — confirma que tienes salida a internet y DNS funcionando.
3. El daemon creó un contenedor a partir de esa imagen, lo ejecutó, y el contenedor imprimió su mensaje y terminó — confirma el ciclo completo de contenedores funcionando de punta a punta.

**Verifica que la imagen quedó descargada localmente:**
```bash
docker images
```
→ Deberías ver `hello-world` en la lista. Puedes borrar el contenedor de prueba ya usado con `docker ps -a` (para ver contenedores detenidos) y `docker rm <container_id>` — no es necesario mantenerlo.

---

### 4.2 — Imagen fácil: MySQL

**1. Descarga la imagen oficial de MySQL desde Docker Hub**

```bash
docker pull mysql
```
→ Se usó el Docker oficial para MySQL desde Docker Hub (`docker pull` descarga la imagen sin correrla todavía). Página oficial de la imagen: **[hub.docker.com/_/mysql](https://hub.docker.com/_/mysql)** — ahí están documentadas todas las variables de entorno disponibles y las versiones/tags soportados.

**2. Instala el cliente de MySQL en el sistema (para poder conectarte desde fuera del contenedor)**

```bash
sudo apt install mysql-client
```
→ Se descargó con `apt install mysql` para poder ingresar al contenedor de Docker desde la terminal del servidor con el comando `mysql`, en vez de depender únicamente de `docker exec`.

**3. Levanta el contenedor con nombre y contraseña**

```bash
docker run --name database -e MYSQL_ROOT_PASSWORD=12345 -d mysql
```
→ Desglose:
- `--name database`: le da un nombre fijo al contenedor (en vez de un nombre aleatorio autogenerado), para poder referenciarlo fácil en comandos posteriores (`docker logs database`, `docker stop database`, etc.).
- `-e MYSQL_ROOT_PASSWORD=12345`: variable de entorno obligatoria — MySQL no arranca sin ella, define la contraseña del usuario `root`.
- `-d`: corre en segundo plano (detached).

**Verifica que quedó corriendo:**
```bash
docker ps
```

**Conéctate — método 1: desde dentro del contenedor con `docker exec`**
```bash
docker exec -it database mysql -uroot -p
```
→ Te pedirá la contraseña (`12345` en este caso). Sal con `exit` o `\q`.

**Conéctate — método 2: desde el host, usando el cliente `mysql` instalado en el paso 2**

Primero necesitas la IP interna del contenedor (la que Docker le asignó en su red):

```bash
docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' database
```
→ Devuelve algo como `172.17.0.2` — es la IP dentro de la red bridge por defecto de Docker (`docker0`), no la IP pública del servidor.

Con esa IP, conéctate usando el cliente `mysql` que instalaste en el host (no `docker exec`):

```bash
mysql -u root -h 172.17.0.2 -p12345
```
→ Desglose:
- `-u root`: usuario.
- `-h 172.17.0.2`: host — la IP del contenedor obtenida arriba (ajusta si la tuya es distinta).
- `-p12345`: contraseña **pegada directamente al flag**, sin espacio (`-p12345`, no `-p 12345`). Si pones espacio, `mysql` interpreta lo que sigue como un argumento distinto y te pide la contraseña interactivamente en su lugar.

**Nota de seguridad**: pasar la contraseña directo en el comando (`-p12345`) la deja visible en el historial de la terminal (`history`) y en la lista de procesos (`ps aux`) mientras corre. Para uso real (no solo práctica), es más seguro usar `-p` solo (sin el valor pegado) y escribirla cuando la pida, o usar variables de entorno/archivos de configuración (`~/.my.cnf`).

**Diferencia entre los dos métodos**: el método 1 (`docker exec`) siempre funciona sin importar la IP del contenedor, porque Docker resuelve el nombre internamente. El método 2 (IP directa) es útil para confirmar que el contenedor expone la conexión correctamente a nivel de red — pero si el contenedor se reinicia, la IP puede cambiar, así que no la des por fija en scripts o configuraciones permanentes.


### 4.3 — Docker Compose: instalación oficial y ejemplos paso a paso

#### 4.3.0 — Instalación (documentación oficial)

Se instaló siguiendo la documentación oficial: **[docs.docker.com/compose/install/linux](https://docs.docker.com/compose/install/linux/)**.

```bash
sudo apt-get update
sudo apt-get install docker-compose-plugin
```
→ Instala el plugin de Compose desde el repositorio de Docker ya registrado (si seguiste la sección 4.0 con `get-docker.sh`, este paquete probablemente ya viene instalado — este comando no hace daño de todos modos, `apt` simplemente confirma que ya está en su última versión).

**Verifica la instalación:**
```bash
docker compose version
```
→ Debe mostrar un número de versión (ej. `Docker Compose version v2.x.x`), sin errores. Si da `is not a docker command`, revisa la sección 4.0 — significa que el repositorio de Docker no quedó registrado en `apt` (mismo diagnóstico del Incidente #13 en la bitácora).

---

#### 4.3.1 — Ejemplo 1: un servicio simple (nginx)

El flujo de trabajo típico con Compose es: editar el archivo con `nano`, bajar el stack anterior (si había uno), y levantar el nuevo. Así se probó cada ejemplo de esta sección.

**Crea el archivo:**
```bash
mkdir -p /opt/apps/compose-lab
cd /opt/apps/compose-lab
nano compose.yaml
```

**Contenido:**
```yaml
services:
  web:
    image: nginx:latest
    ports:
      - "8080:80"
```
→ Un solo servicio (`web`), usando la imagen oficial de nginx, exponiendo el puerto 80 del contenedor como 8080 en el host.

**Levanta el stack:**
```bash
docker compose up -d
```

**Verifica:**
```bash
curl http://localhost:8080
```
→ Debe devolver el HTML de bienvenida de nginx.

---

#### 4.3.2 — Ejemplo 2: build de un Dockerfile con Compose

En este caso, se hace un build de un Dockerfile que está en la misma carpeta que el fichero compose. Para eso, se agrega la clave `build` en el servicio en vez de `image`.

**Baja el stack anterior antes de cambiar de ejemplo:**
```bash
docker compose down
```

**Edita el archivo:**
```bash
nano compose.yaml
```

**Nuevo contenido:**
```yaml
services:
  web:
    build: .
    ports:
      - "8080:80"
```
→ `build: .` le dice a Compose que, en vez de descargar una imagen ya hecha, construya una nueva usando el `Dockerfile` que debe existir en el mismo directorio (`.` = directorio actual, el mismo build context que ya viste con `docker build`). Compose maneja el `docker build` internamente antes de levantar el contenedor.

**Levanta (esta vez sí construye la imagen primero):**
```bash
docker compose up -d
```
→ Necesitas tener un `Dockerfile` válido en `/opt/apps/compose-lab` para que este ejemplo funcione — sin uno, Compose falla con `Dockerfile not found`.

---

#### 4.3.3 — Ejemplo 3: varios servicios y enrutamiento entre contenedores

Se completa el ejemplo anterior con otro contenedor, para hacer peticiones al servicio nginx y demostrar cómo Compose resuelve el enrutamiento entre servicios automáticamente.

**Baja el stack anterior:**
```bash
docker compose down
```

**Edita el archivo:**
```bash
nano compose.yaml
```

**Nuevo contenido:**
```yaml
services:
  web:
    image: nginx
  test:
    image: nginx
```
→ Dos servicios: `web` (el servidor nginx) y `test` (el contenedor desde el que se hacen las peticiones).

> **Nota**: para que el comando `curl` del paso siguiente funcione dentro del contenedor `test`, esa imagen necesita tener `curl` instalado — la imagen base de nginx no lo incluye por defecto. Si `curl` no está disponible, usa una imagen que sí lo tenga (ej. `curlimages/curl`) o instálalo con un Dockerfile propio para ese servicio.

**Levanta el stack:**
```bash
docker compose up -d
```

**Genera un terminal interactivo dentro del contenedor `test`:**
```bash
docker compose exec test sh
```
→ `exec` abre una sesión interactiva dentro de un contenedor **ya corriendo** del stack (equivalente a `docker exec -it`, pero usando el nombre del servicio en vez del nombre/ID del contenedor). Aquí, `test` es el nombre del servicio al que queremos entrar.

**Desde dentro del contenedor `test`, haz la petición al servicio `web` por nombre:**
```bash
curl web:80
```
→ Aquí está la parte clave: `web` es el nombre del servicio definido en el `compose.yaml`, **no una IP**. Compose crea automáticamente una red interna donde cada servicio puede resolver a los demás por su nombre — nunca hay que especificar IPs manualmente al trabajar con Compose (esto también aplica a Kubernetes y otros orquestadores, donde el mismo patrón de descubrimiento por nombre de servicio es estándar).

---

#### 4.3.4 — Verificar el estado de los servicios

Importante después de cualquier instalación o cambio, para confirmar que todo el stack está realmente corriendo:

```bash
docker compose ps
```
→ Muestra el estado de los servicios definidos en el compose (a diferencia de `docker ps`, que muestra TODOS los contenedores del sistema, este filtra solo los de este proyecto/carpeta).

```bash
docker compose logs -f
```
→ Logs agregados de todos los servicios del stack en tiempo real — útil para depurar cuando un servicio no arranca bien.

---

#### 4.3.5 — Ejemplo más completo: WordPress + MariaDB

Como ejemplo más completo, se desplegó WordPress con una base de datos MariaDB, con los servicios definidos en bloques separados dentro del mismo `compose.yaml`.

**Baja el stack anterior:**
```bash
docker compose down
```

**Archivo completo:**
```yaml
services:
  db:
    # We use a mariadb image which supports both amd64 & arm64 architecture
    image: mariadb:10.6.4-focal
    command: '--default-authentication-plugin=mysql_native_password'
    volumes:
      - db_data:/var/lib/mysql
    restart: always
    environment:
      - MYSQL_ROOT_PASSWORD=54321
      - MYSQL_DATABASE=wordpress
      - MYSQL_USER=wordpress
      - MYSQL_PASSWORD=54321
    expose:
      - "3306"
      - "33060"

  wordpress:
    image: wordpress:latest
    volumes:
      - wp_data:/var/www/html
    ports:
      - "8080:80"
    restart: always
    environment:
      - WORDPRESS_DB_HOST=db
      - WORDPRESS_DB_USER=wordpress
      - WORDPRESS_DB_PASSWORD=wordpress
      - WORDPRESS_DB_NAME=wordpress

volumes:
  db_data:
  wp_data:
```

**Desglose bloque por bloque:**

**Bloque `db` (MariaDB):**
- `image: mariadb:10.6.4-focal`: imagen oficial de MariaDB, con soporte para arquitecturas `amd64` y `arm64` — importante si tu servidor no es Intel/AMD tradicional (por ejemplo, un Raspberry Pi o una instancia ARM en la nube).
- `command: '--default-authentication-plugin=mysql_native_password'`: sobreescribe el comando de arranque del contenedor, forzando el plugin de autenticación clásico de MySQL — necesario para compatibilidad con WordPress, que espera ese método.
- `volumes: - db_data:/var/lib/mysql`: persiste los datos de la base en el volumen nombrado `db_data`, para no perderlos si el contenedor se recrea.
- `restart: always`: el contenedor se reinicia automáticamente ante cualquier caída, incluso después de un reboot del servidor (más agresivo que `unless-stopped`, que ya viste en Docker run — `always` ignora incluso si tú lo detuviste manualmente).
- `environment`: variables que MariaDB usa en su primer arranque para crear el usuario root, la base de datos inicial, y el usuario de aplicación (`wordpress`).
- `expose: - "3306" - "33060"`: a diferencia de `ports`, `expose` **no publica el puerto al host** — solo lo hace accesible para otros contenedores en la misma red de Compose. Es la elección correcta para una base de datos que solo debe ser alcanzable por `wordpress`, no desde internet.

**Bloque `wordpress`:**
- `image: wordpress:latest`: imagen oficial de WordPress.
- `volumes: - wp_data:/var/www/html`: persiste los archivos de WordPress (temas, plugins, uploads) en el volumen `wp_data`.
- `ports: - "8080:80"`: a diferencia de `expose` en el bloque de `db`, aquí sí se usa `ports` porque WordPress necesita ser accesible desde el navegador — mapea el puerto 8080 del host al 80 del contenedor.
- `environment`: `WORDPRESS_DB_HOST=db` es la parte clave — `db` es el nombre del servicio de MariaDB definido arriba, así que WordPress se conecta a la base de datos por nombre de servicio, sin IPs (mismo patrón visto en el Ejemplo 3).

**Bloque `volumes` (nivel raíz, fuera de `services`):**
```yaml
volumes:
  db_data:
  wp_data:
```
→ Declara los dos volúmenes nombrados usados arriba. Sin este bloque, Compose los crearía igual de forma implícita, pero declararlos explícitamente es buena práctica — deja claro en el archivo qué datos persisten.

**Levanta el stack completo:**
```bash
docker compose up -d
```

**Verifica:**
```bash
docker compose ps
```
→ Deben aparecer ambos servicios (`db` y `wordpress`) con estado `Up`.

Abre `http://<IP_SERVIDOR>:8080` en el navegador — debe cargar el instalador inicial de WordPress.

---

#### 4.3.6 — Comandos generales de mantenimiento

**Editar y volver a aplicar cambios:**
```bash
nano compose.yaml
docker compose up -d
```
→ Compose detecta automáticamente qué cambió y solo recrea los servicios afectados, sin necesidad de bajar todo primero.

**Detener y limpiar:**
```bash
docker compose down
```
→ Detiene y elimina los contenedores del stack (conserva las imágenes). Para eliminar también volúmenes asociados (⚠️ borra los datos, como la base de datos de WordPress):
```bash
docker compose down -v
```

---

#### 4.3.7 — Referencias

Se investigó y se tomaron referencias de la documentación oficial de Docker y de esta guía comunitaria:
- [docs.docker.com/compose/install/linux](https://docs.docker.com/compose/install/linux/) — instalación oficial
- [github.com/pabpereza/pabpereza — Docker Compose](https://github.com/pabpereza/pabpereza/blob/main/docs/cursos/docker/112.Docker_compose.md) — guía de referencia para los ejemplos de build, multi-servicio y enrutamiento

---

## FASE 5 — Kubernetes

**Referencias oficiales:**
- [docs.k3s.io](https://docs.k3s.io) — documentación oficial de k3s (instalación, arquitectura, configuración, HA, upgrades)
- [github.com/k3s-io/k3s](https://github.com/k3s-io/k3s) — repositorio del proyecto, incluye el `install.sh` y notas de release
- [kubernetes.io/docs](https://kubernetes.io/docs/home/) — documentación oficial de Kubernetes "upstream" (conceptos, `kubectl`, manifiestos) — k3s es una distribución conforme de Kubernetes, así que la mayoría de conceptos (Pods, Deployments, Services) aplican igual, solo cambia el método de instalación/arquitectura interna

**Nota**: para un solo servidor de aprendizaje, usa **k3s** (Kubernetes liviano) en vez de kubeadm completo.

```bash
curl -sfL https://get.k3s.io | sh -
sudo k3s kubectl get nodes
```
→ Instala cluster de un nodo. **Por qué k3s**: kubeadm requiere ≥2 CPU/2GB por nodo y más pasos; k3s es producción-viable para clusters pequeños/edge.

```bash
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
export KUBECONFIG=~/.kube/config
```
→ Configura `kubectl` para no depender de `sudo k3s kubectl` cada vez.

**Crea una carpeta para tus manifiestos de Kubernetes:**
```bash
mkdir -p /opt/k8s
cd /opt/k8s
nano deployment.yaml
```
→ Convención similar a `/opt/apps` para Docker y `/opt/scripts` para bash/Python — mantiene cada tipo de artefacto en su propio directorio. Aquí es donde escribes el contenido de abajo.

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: miapp
spec:
  replicas: 2
  selector:
    matchLabels: {app: miapp}
  template:
    metadata:
      labels: {app: miapp}
    spec:
      containers:
      - name: miapp
        image: nginx:latest
        resources:
          requests: {cpu: "100m", memory: "128Mi"}
          limits: {cpu: "500m", memory: "256Mi"}
        livenessProbe:
          httpGet: {path: /, port: 80}
          initialDelaySeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: miapp-svc
spec:
  selector: {app: miapp}
  ports: [{port: 80, targetPort: 80}]
  type: ClusterIP
```
→ `resources` evita que un pod consuma todo el nodo (**síntoma que previene**: noisy neighbor). `livenessProbe` reinicia el pod si deja de responder. Se usa `nginx:latest` (imagen pública real) en vez de una imagen propia como `miapp:1.0` — para que este ejemplo funcione tal cual sin depender de haber construido y publicado tu propia imagen primero.

```bash
kubectl apply -f deployment.yaml
kubectl get pods -w
```
→ Aplica manifiesto; `-w` observa cambios en tiempo real (útil viendo rollouts).

**Fix si sale `ErrImagePull` / `ImagePullBackOff`**

```
miapp-668ff4fdbf-99z8d   0/1   ErrImagePull       0   9s
miapp-668ff4fdbf-99z8d   0/1   ImagePullBackOff   0   15s
```
→ Significa que k3s no pudo descargar la imagen especificada en `image:`. Este error salía con `image: miapp:1.0` porque esa imagen **nunca fue construida ni publicada** en ningún registro — era solo un nombre de ejemplo genérico. `ImagePullBackOff` es el estado de "reintento con espera exponencial" que Kubernetes usa después de varios `ErrImagePull` seguidos, no un error nuevo.

**Diagnóstico:**
```bash
kubectl describe pod <nombre-del-pod>
```
→ Busca la sección `Events` al final — muestra el mensaje exacto del intento de pull (ej. `manifest unknown`, `pull access denied`, `not found`).

**Causas típicas y fix:**
1. **Typo en el nombre o tag de la imagen** — revisa que `image:` en el YAML coincida exactamente con una imagen que existe en Docker Hub (o el registro que uses).
2. **Imagen construida localmente con `docker build`, pero k3s no la ve** — esta es la causa más común y la más confusa al principio: **k3s usa su propio runtime `containerd`, completamente separado del daemon de Docker**. Una imagen que existe en `docker images` (construida con `docker build -t miapp:1.0 .`) **no es visible automáticamente para k3s** — viven en dos "almacenes" de imágenes distintos, aunque estén en el mismo servidor. Para usar una imagen local en k3s, hay que importarla explícitamente:
   ```bash
   docker save miapp:1.0 | sudo k3s ctr images import -
   ```
   → Exporta la imagen del daemon de Docker y la importa al containerd de k3s. Alternativa más estándar en producción: subir la imagen a un registro (Docker Hub, GitHub Container Registry, etc.) con `docker push`, y referenciar esa ruta completa en el YAML (ej. `image: usuario/miapp:1.0`) — así cualquier nodo del cluster puede descargarla sin depender de que ya exista localmente.
3. **Imagen privada sin credenciales configuradas** — si usas un registro privado, k3s necesita un `imagePullSecret` configurado; sin él, el pull falla con `pull access denied` aunque la imagen exista.

```bash
kubectl describe pod <pod-name>
kubectl logs <pod-name> --previous
```
→ **Fix estándar cuando un pod crashea**: `describe` muestra eventos (OOMKilled, ImagePullBackOff, etc.), `--previous` muestra logs del contenedor anterior al último crash.

```bash
kubectl rollout status deployment/miapp
kubectl rollout undo deployment/miapp
```
→ Verifica estado de despliegue; `undo` hace rollback inmediato a la versión anterior. **Uso**: deploy malo en producción.

### 5.1 — Cómo verificar si un pod está funcionando

Distintos niveles de verificación, de lo rápido a lo detallado.

**1. Vista rápida — estado general**

```bash
kubectl get pods
```
→ Columna clave: `STATUS`, debe decir `Running`. La columna `READY` (ej. `1/1`) confirma que el contenedor **dentro** del pod pasó su `readinessProbe` (si tiene una configurada) — `0/1` con estado `Running` significa que el pod arrancó, pero el contenedor todavía no está listo para recibir tráfico.

```bash
kubectl get pods -o wide
```
→ Agrega columnas extra: en qué nodo corre, su IP interna, etc. — útil en clusters con más de un nodo.

**2. Ver en tiempo real mientras cambia**

```bash
kubectl get pods -w
```
→ `-w` (watch) deja la terminal viendo cambios de estado en vivo, útil justo después de un `apply` o `rollout`.

**3. Detalle completo — cuando algo no está bien**

```bash
kubectl describe pod <nombre-del-pod>
```
→ Muestra todo: eventos recientes (al final, sección `Events`), qué imagen usa, resources, probes configuradas, y por qué falló si falló. Es el primer comando a correr cuando `STATUS` no dice `Running`.

**4. Logs del contenedor — confirmar que la aplicación en sí funciona bien, no solo que el proceso arrancó**

```bash
kubectl logs <nombre-del-pod>
```
```bash
kubectl logs -f <nombre-del-pod>
```
→ `-f` en vivo, igual que `docker logs -f`. Esto confirma si la app está sirviendo tráfico correctamente, más allá de que Kubernetes reporte `Running`.

**5. Prueba funcional real — confirmar que responde a tráfico**

```bash
kubectl port-forward <nombre-del-pod> 8080:80
```
→ Mapea el puerto 80 del pod al 8080 de tu máquina temporalmente. **Importante**: el formato es `<puerto-local>:<puerto-del-pod>` — si escribes solo un número (`kubectl port-forward <pod> 8080`), Kubernetes usa ese mismo número para ambos lados (local **y** del pod), lo cual falla si tu contenedor no escucha exactamente en 8080 (el `nginx:latest` del manifiesto de esta fase escucha en el puerto **80**, no 8080 — por eso el formato con los dos puertos, `8080:80`, es el correcto).

Luego, en otra terminal:
```bash
curl http://localhost:8080
```
→ Esta es la prueba más confiable: no solo confirma que el pod "existe", sino que responde tráfico real — equivalente al `curl` que ya usaste para validar el contenedor `nginx-test` de Docker.

**Fix si sale `bind: address already in use`**

```
Unable to listen on port 8080: Listeners failed to create with the following errors:
[unable to create listener: Error listen tcp4 127.0.0.1:8080: bind: address already in use ...]
```
→ El puerto local **8080 ya está ocupado por otro proceso** en tu servidor — `kubectl port-forward` no puede escuchar ahí de nuevo. Es un conflicto de puerto en el host, no un problema del pod ni de Kubernetes.

**Diagnóstico — revisa qué ya está usando el 8080:**
```bash
sudo ss -tlnp | grep 8080
```
→ Muy probablemente sea el contenedor `nginx-test` de Docker (FASE 4) o el stack de WordPress (sección 4.3.5), ambos mapeados a `8080:80` en el host — si dejaste alguno corriendo, sigue ocupando ese puerto a nivel de sistema operativo, sin relación con Kubernetes.

```bash
docker ps
```
→ Confirma si alguno de esos contenedores sigue activo.

**Fix — dos opciones:**

**Opción 1**: usa un puerto local distinto para el `port-forward` (no necesita coincidir con el puerto del pod):
```bash
kubectl port-forward <nombre-del-pod> 8081:80
curl http://localhost:8081
```

**Opción 2**: libera el puerto 8080 deteniendo el contenedor de Docker que lo está usando:
```bash
docker stop nginx-test
kubectl port-forward <nombre-del-pod> 8080:80
```

**Resumen — qué mirar según lo que necesites confirmar:**

| Quieres saber | Comando |
|---|---|
| ¿Está corriendo? | `kubectl get pods` |
| ¿Por qué no arrancó? | `kubectl describe pod <nombre>` |
| ¿Qué está imprimiendo la app? | `kubectl logs <nombre>` |
| ¿Responde tráfico de verdad? | `kubectl port-forward` + `curl` |

---

## FASE 6 — Ansible: automatización de infraestructura

**Referencias oficiales:**
- [docs.ansible.com](https://docs.ansible.com/) — documentación oficial de Ansible
- [github.com/ansible/ansible](https://github.com/ansible/ansible) — repositorio principal (ansible-core)
- [ansible.builtin.file](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/file_module.html) · [ansible.builtin.template](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/template_module.html) · [community.docker.docker_container](https://docs.ansible.com/projects/ansible/latest/collections/community/docker/docker_container_module.html) — módulos usados en esta fase
- [github.com/ansible-collections/community.docker](https://github.com/ansible-collections/community.docker) — repositorio de la colección Docker de Ansible

```bash
sudo apt install -y ansible
```
→ En el nodo **control** (no en los servidores gestionados).

**Crea una carpeta para tus archivos de Ansible:**
```bash
mkdir -p /opt/ansible
cd /opt/ansible
nano inventory.ini
```
→ Misma convención que el resto del playbook: `/opt/apps` para Docker, `/opt/scripts` para bash/Python, `/opt/k8s` para manifiestos de Kubernetes, y ahora `/opt/ansible` para el inventario y los playbooks. Aquí es donde escribes el contenido de abajo.

```ini
# inventory.ini
[web]
srv-prod-01 ansible_connection=local

[web:vars]
ansible_python_interpreter=/usr/bin/python3
```
→ `ansible_connection=local` le dice a Ansible que ejecute los módulos **directamente en esta máquina**, sin pasar por SSH. En este homelab, el nodo de control y el nodo gestionado son el mismo servidor, así que no tiene sentido configurar SSH solo para conectarte a ti mismo — Ansible corre las tareas localmente, con el mismo resultado.

> **Nota — entornos con varios servidores reales**: en un cluster con más de un servidor, sí necesitarías SSH real entre el nodo de control y cada nodo gestionado. En ese caso, el inventario usaría `ansible_host=<IP-del-servidor>`, `ansible_user=<usuario>` y `ansible_port=<puerto-ssh>` en vez de `ansible_connection=local` — y ese servidor gestionado necesitaría tener `openssh-server` instalado y corriendo (`sudo apt install -y openssh-server && sudo systemctl enable ssh --now`), con tu llave pública SSH agregada a su `~/.ssh/authorized_keys`.

```bash
ansible web -i inventory.ini -m ping
```
→ Prueba de conectividad. Con `ansible_connection=local`, debe responder `SUCCESS` con `"ping": "pong"` de inmediato — no hay handshake SSH que pueda fallar.

**Fix si sale `sudo: a password is required` o similar al usar `become: true` más adelante**

Con conexión local, `become` (usado en el playbook de abajo) llama a `sudo` directamente en tu sesión actual. Si tu usuario necesita contraseña para `sudo` (no tiene NOPASSWD configurado), Ansible te la pedirá de forma interactiva:
```bash
ansible-playbook -i inventory.ini playbook.yml --ask-become-pass
```
→ `--ask-become-pass` hace que Ansible pregunte la contraseña de `sudo` antes de ejecutar, en vez de fallar en silencio.

**Crea el playbook en la misma carpeta:**
```bash
nano playbook.yml
```

```yaml
# playbook.yml
- hosts: web
  become: true
  tasks:
    - name: Actualizar paquetes
      apt: {update_cache: yes, upgrade: dist}

    - name: Instalar Docker
      apt: {name: docker.io, state: present}

    - name: Asegurar que Docker esté activo
      systemd: {name: docker, state: started, enabled: true}

    - name: Crear directorio de la app
      file:
        path: /opt/app
        state: directory
        mode: "0755"

    - name: Copiar configuración de la app
      template:
        src: app.env.j2
        dest: /opt/app/.env
        mode: "0600"
      notify: reiniciar app

  handlers:
    - name: reiniciar app
      docker_container:
        name: miapp
        image: nginx:latest
        state: started
        restart: true
```
→ `become: true` = eleva a sudo al ejecutar (en este caso, en la misma máquina local, gracias a `ansible_connection=local`; en un entorno multi-servidor sería sudo en cada host remoto). `handlers` solo se disparan si la tarea que los `notify` realmente cambió algo (idempotencia). **Concepto clave**: Ansible es declarativo — describes el estado final, no los pasos. La tarea `Crear directorio de la app` (módulo `file`, `state: directory`) es necesaria porque el módulo `template` **no crea directorios intermedios automáticamente** — si `/opt/app` no existe antes de intentar copiar `.env` ahí, falla con `Destination directory /opt/app does not exist`. El handler usa `docker_container` con `image: nginx:latest` (la misma imagen pública ya usada en Docker y Kubernetes) — sin la clave `image:`, el módulo no sabe qué imagen usar si el contenedor `miapp` aún no existe, y falla con `Cannot create container when image is not specified!`.

**Nota importante sobre `--check` con esta tarea**: como el handler crea/reinicia un contenedor Docker (una acción con efecto real), en modo `--check` (dry-run) Ansible puede simularla sin ejecutarla de verdad. Para confirmar que el contenedor realmente queda corriendo, corre también sin `--check`:
```bash
ansible-playbook -i inventory.ini playbook.yml --ask-become-pass
docker ps
```
→ Debe aparecer `miapp` corriendo con la imagen `nginx:latest`.

```bash
ansible-playbook -i inventory.ini playbook.yml --check
```
→ **Dry-run**: muestra qué cambiaría SIN aplicarlo. Úsalo siempre antes de correr en producción.

```bash
ansible-playbook -i inventory.ini playbook.yml
```
→ Ejecución real.

```bash
ansible-vault encrypt secrets.yml
ansible-playbook -i inventory.ini playbook.yml --ask-vault-pass
```
→ Cifra credenciales/secretos en el repo. **Nunca** secretos en texto plano en Git.

### 6.1 — Validación final: confirmar que el contenedor creado por Ansible sigue corriendo

El handler `reiniciar app` del playbook creó el contenedor `miapp` con el módulo `docker_container` — **no** con Docker Compose, así que hay que verificarlo con el comando correcto.

**1. `docker compose ps` no lo va a mostrar — usa `docker ps`**

```bash
docker ps
```
→ `docker compose ps` solo lista contenedores que pertenecen a un proyecto de Compose (creados con `docker compose up` desde un `compose.yaml`). El módulo `docker_container` de Ansible habla directo con la API de Docker, sin pasar por Compose — el contenedor no tiene la etiqueta de proyecto que `compose ps` busca, así que queda invisible ahí aunque esté corriendo bien.

```bash
docker ps -a
```
→ Si `miapp` no aparece corriendo, revisa aquí — puede estar en estado `Exited`.

**2. Si el estado es `Exited`, diagnostica antes de reiniciar a ciegas**

```bash
docker inspect miapp --format='Exit Code: {{.State.ExitCode}} | Error: {{.State.Error}} | OOMKilled: {{.State.OOMKilled}}'
```
→ El `Exit Code` es la pista principal:
- `0` = el proceso terminó normalmente (algo le dijo que parara, no fue un crash)
- `137` = fue matado por el sistema (a menudo memoria — revisa si `OOMKilled` dice `true`)
- Cualquier otro número = el proceso falló con ese código de error

```bash
docker logs miapp
```
→ Casi siempre dice exactamente qué pasó dentro del contenedor.

**3. Causa típica: `restart: true` en el módulo no es una política de reinicio persistente**

```bash
docker inspect miapp --format='RestartPolicy: {{.HostConfig.RestartPolicy.Name}}'
```
→ El `restart: true` que se usó en el handler de Ansible solo le dice a Docker "reinicia el contenedor ahora, una vez", durante la ejecución del playbook — a diferencia de `--restart unless-stopped` (usado en Docker run desde la FASE 4), no configura que el contenedor se reinicie solo ante fallos futuros. Si `miapp` falló después de ese reinicio puntual, se queda en `Exited` sin que nadie lo revise.

**Fix — agrega una política de reinicio real en el playbook:**
```yaml
handlers:
  - name: reiniciar app
    docker_container:
      name: miapp
      image: nginx:latest
      state: started
      restart: true
      restart_policy: unless-stopped
```
→ `restart_policy: unless-stopped` sí es persistente — el contenedor se reinicia automáticamente ante crashes o reboots del servidor, igual que el `--restart unless-stopped` de `docker run`.

**4. Reinicia manualmente y confirma que se mantiene arriba:**
```bash
docker start miapp
docker logs -f miapp
```
→ Déjalo unos segundos observando — si vuelve a salir solo (`Exited` de nuevo), el problema está en la app/imagen, no en la política de reinicio.

---

## FASE 7 — Monitoreo automatizado (Prometheus + Grafana + Node Exporter)

**Referencias oficiales:**
- [prometheus.io/docs](https://prometheus.io/docs/introduction/overview/) — documentación oficial de Prometheus
- [grafana.com/docs](https://grafana.com/docs/) — documentación oficial de Grafana
- [github.com/prometheus/prometheus](https://github.com/prometheus/prometheus) · [github.com/prometheus/node_exporter](https://github.com/prometheus/node_exporter) · [github.com/grafana/grafana](https://github.com/grafana/grafana)
- [grafana.com/grafana/dashboards](https://grafana.com/grafana/dashboards/) — repositorio de dashboards comunitarios (incluye el dashboard 1860 usado en esta fase)

```bash
sudo useradd --no-create-home --shell /usr/sbin/nologin node_exporter
```
→ Usuario de sistema sin login ni home, por seguridad (servicios no deben correr como usuarios interactivos).

### 7.1 — Instalar node_exporter, paso a paso

**1. Resuelve la versión más reciente y descarga**

```bash
cd ~
NODE_EXPORTER_VERSION=$(curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest | grep '"tag_name"' | cut -d '"' -f4 | sed 's/^v//')
echo "Versión detectada: $NODE_EXPORTER_VERSION"
curl -LO "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
```
→ La versión se resuelve dinámicamente consultando la API de GitHub (`tag_name` del último release) en vez de escribir un número de versión fijo en la URL — un número fijo combinado con `/latest/download/` se desactualiza tarde o temprano: si la versión "latest" real ya no coincide con la que se escribió a mano, GitHub responde con una página HTML de error 404 en vez del archivo, y `curl -O` la guarda igual con extensión `.tar.gz`.

**2. Verifica que descargaste un archivo real, no una página de error, ANTES de extraer**

```bash
file node_exporter-*.tar.gz
```
→ Debe decir `gzip compressed data`. Si dice `HTML document` o `ASCII text`, descargaste una página de error 404 — bórrala y repite el paso 1:
```bash
rm -f node_exporter-*.tar.gz
```

**3. Extrae el archivo**

```bash
tar xvf node_exporter-*.tar.gz
```

**4. Confirma que el binario existe dentro de la carpeta extraída ANTES de moverlo**

```bash
ls -la ~ | grep node_exporter
```
→ Debe mostrar una carpeta `node_exporter-<versión>.linux-amd64/` (sin extensión) además del `.tar.gz` original. Verifica que el binario esté dentro:
```bash
ls -l ~/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/
```
→ Debe listar `node_exporter` (el binario ejecutable), junto con `LICENSE` y `NOTICE`.

**5. Mueve el binario a `/usr/local/bin`**

```bash
sudo mv ~/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/
```
→ Se usa la ruta completa con la variable `$NODE_EXPORTER_VERSION` (en vez del comodín `node_exporter-*/node_exporter`) para apuntar sin ambigüedad a la carpeta exacta, sobre todo si quedaron restos de intentos anteriores con otras versiones en el mismo directorio.

**6. Verifica que el binario quedó instalado y responde**

```bash
node_exporter --version
```
→ Debe imprimir la versión sin error `command not found`. Si falla, confirma que `/usr/local/bin` esté en tu `PATH` (`echo $PATH`) o prueba con la ruta absoluta: `/usr/local/bin/node_exporter --version`.

**7. Limpieza — ya no necesitas la carpeta ni el `.tar.gz`**

```bash
rm -rf ~/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64 ~/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
```

**Crea el archivo de definición del servicio:**
```bash
sudo nano /etc/systemd/system/node_exporter.service
```
→ A diferencia de `/opt/scripts`, `/opt/k8s` o `/opt/ansible` (carpetas propias tuyas), los archivos `.service` de systemd **deben** vivir en `/etc/systemd/system/` — es la ruta estándar donde systemd busca definiciones de servicios de usuario/terceros (distinta de `/lib/systemd/system/`, reservada para servicios que vienen empaquetados con `apt`). Por eso el comando lleva `sudo nano` directo, sin `mkdir` previo — el directorio ya existe en cualquier Ubuntu.

```ini
# /etc/systemd/system/node_exporter.service
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
```
→ Pega este contenido dentro de `nano` y guarda como siempre: `Ctrl+O` → `Enter` → `Ctrl+X`.

```bash
sudo systemctl daemon-reload
sudo systemctl enable node_exporter --now
```
→ Lo convierte en servicio systemd persistente (sobrevive reboots).

**Crea una carpeta para el stack de monitoreo:**
```bash
mkdir -p /opt/monitoring
cd /opt/monitoring
nano docker-compose.monitoring.yml
```
→ Misma convención que el resto del playbook: `/opt/apps` para Docker, `/opt/scripts` para bash/Python, `/opt/k8s` para Kubernetes, `/opt/ansible` para Ansible, y ahora `/opt/monitoring` para Prometheus/Grafana. Aquí es donde escribes el contenido de abajo.

```yaml
# docker-compose.monitoring.yml
services:
  prometheus:
    image: prom/prometheus
    volumes: ["./prometheus.yml:/etc/prometheus/prometheus.yml"]
    ports: ["9090:9090"]
  grafana:
    image: grafana/grafana
    ports: ["3000:3000"]
    volumes: ["grafana-data:/var/lib/grafana"]
volumes:
  grafana-data:
```
→ Stack de monitoreo vía Docker (más simple que instalar todo nativo). Guarda igual que siempre: `Ctrl+O` → `Enter` → `Ctrl+X`.

**Crea el segundo archivo, en la misma carpeta:**
```bash
nano prometheus.yml
```
→ **Importante**: debe llamarse exactamente `prometheus.yml` y estar en la **misma carpeta** que `docker-compose.monitoring.yml` — el `volumes:` de arriba lo referencia con una ruta relativa (`./prometheus.yml`), así que si lo creas en otro directorio, Compose no lo va a encontrar al levantar el stack.

```yaml
# prometheus.yml
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: "node"
    static_configs:
      - targets: ["<IP_SERVIDOR>:9100"]
  - job_name: "kubernetes"
    static_configs:
      - targets: ["<IP_SERVIDOR>:10250"]
```
→ Define cada cuánto y de dónde Prometheus recolecta métricas (`scrape`).

**Verifica que ambos archivos quedaron en la misma carpeta antes de levantar el stack:**
```bash
ls -la /opt/monitoring/
```
→ Debe mostrar `docker-compose.monitoring.yml` y `prometheus.yml` juntos.

```bash
docker compose -f docker-compose.monitoring.yml up -d
```
→ Levanta Prometheus y Grafana en segundo plano. Este comando solo crea los contenedores — los pasos siguientes son para confirmar que están accesibles y conectar uno con el otro.

### 7.2 — Levantar el stack y acceder vía navegador, paso a paso

**1. Verifica que ambos contenedores quedaron corriendo**

```bash
docker compose -f docker-compose.monitoring.yml ps
```
→ Debe mostrar `prometheus` y `grafana` con estado `Up`. Si alguno no aparece o está `Exited`, revisa sus logs antes de continuar:
```bash
docker compose -f docker-compose.monitoring.yml logs prometheus
docker compose -f docker-compose.monitoring.yml logs grafana
```

**2. Confirma que los puertos están expuestos correctamente**

```bash
sudo ss -tlnp | grep -E '9090|3000'
```
→ Debe mostrar ambos puertos escuchando (`9090` para Prometheus, `3000` para Grafana).

**3. Accede a Prometheus desde el navegador**

Abre en tu navegador:
```
http://<IP_SERVIDOR>:9090
```
→ Reemplaza `<IP_SERVIDOR>` por la IP real de tu servidor (`hostname -I` si no la tienes a mano). Debe cargar la interfaz web de Prometheus.

**Ejemplo con una IP real** (asumiendo `hostname -I` devolvió `192.168.x.x` — típico en modo Adaptador Puente de VirtualBox, ya visible directo desde tu red local):
```
http://192.168.x.x:9090
```

**Confirma que Prometheus está recolectando métricas de tus targets:**
```
http://<IP_SERVIDOR>:9090/targets
```
→ Ejemplo: `http://192.168.x.x:9090/targets`. Esta página lista cada `job` definido en `prometheus.yml` (`node`, `kubernetes`) con su estado: **`UP`** en verde significa que Prometheus está scrapeando esa métrica exitosamente; **`DOWN`** en rojo significa que no puede alcanzar ese target — revisa la IP/puerto en `prometheus.yml` y que `node_exporter` esté corriendo ahí (sección 7.1).

**Prueba una consulta simple**, directo en la barra de búsqueda de la UI de Prometheus (pestaña "Graph"):
```
node_cpu_seconds_total
```
→ Si ves resultados con datos, confirma que las métricas de `node_exporter` están llegando de punta a punta.

**4. Accede a Grafana desde el navegador**

Abre en tu navegador:
```
http://<IP_SERVIDOR>:3000
```
→ Ejemplo: `http://192.168.x.x:3000`. Pantalla de login de Grafana. Credenciales por defecto en el primer acceso:
- Usuario: `admin`
- Contraseña: `admin`

→ Grafana te pedirá cambiar la contraseña inmediatamente después del primer login — hazlo, no dejes la contraseña por defecto en un servidor accesible por red, aunque sea un lab.

**5. Conecta Grafana con Prometheus como fuente de datos**

Dentro de la UI de Grafana:
```
Menú lateral (ícono de engranaje) → Connections → Data Sources → Add data source → Prometheus
```
→ En **URL**, escribe:
```
http://prometheus:9090
```
→ **Importante**: aquí usas `prometheus` (el nombre del servicio en `docker-compose.monitoring.yml`), **no** `localhost` ni la IP del servidor — Grafana corre dentro de la misma red de Docker Compose que Prometheus, así que se alcanzan por nombre de servicio, igual que viste con `curl web:80` en el Ejemplo 3 de Docker Compose (sección 4.3.3).

Click en **Save & Test** al final del formulario — debe confirmar `Successfully queried the Prometheus API`.

**6. Importa el dashboard estándar de la industria**

```
Menú lateral → Dashboards → New → Import
```
→ En el campo "Import via grafana.com", escribe el ID del dashboard:
```
1860
```
→ Este es el dashboard **Node Exporter Full**, el más usado de la comunidad para visualizar métricas de `node_exporter` — no hace falta construir el tuyo desde cero. Click en **Load**, selecciona la fuente de datos Prometheus que agregaste en el paso 5, y click en **Import**.

**7. Confirma que el dashboard muestra datos reales**

→ Debe cargar gráficos de CPU, memoria, disco y red del servidor, con valores actualizándose cada `scrape_interval` (15s, según `prometheus.yml`). Si los gráficos aparecen vacíos ("No data"), vuelve al paso 3 y confirma que el target `node` esté en `UP` en `/targets` — un dashboard vacío casi siempre significa que la fuente de datos no tiene métricas que mostrar, no un problema del dashboard en sí.

### 7.3 — Alertas básicas, paso a paso

**1. Crea el archivo en la misma carpeta del stack de monitoreo**

```bash
cd /opt/monitoring
nano alert.rules.yml
```
→ Mismo directorio que `docker-compose.monitoring.yml` y `prometheus.yml` (sección 7.2, paso 1) — Prometheus necesita poder montar este archivo desde ahí.

**Contenido:**
```yaml
# alert.rules.yml
groups:
  - name: node-alerts
    rules:
      - alert: DiscoLleno
        expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 < 15
        for: 5m
        labels: {severity: critical}
        annotations: {summary: "Disco con menos de 15% libre en {{ $labels.instance }}"}

      - alert: CPUAlta
        expr: 100 - (avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 85
        for: 10m
        labels: {severity: warning}
```
→ `for: 5m` evita falsos positivos por picos momentáneos (**patrón clave**: alertar sobre estado sostenido, no instantáneo). Guarda igual que siempre: `Ctrl+O` → `Enter` → `Ctrl+X`.

**2. Conecta el archivo de reglas a Prometheus — dos cambios necesarios**

Este archivo, por sí solo, no hace nada todavía: Prometheus no lo lee a menos que se lo indiques explícitamente en dos lugares.

**Primero, referencia el archivo dentro de `prometheus.yml`:**
```bash
nano prometheus.yml
```
Agrega la línea `rule_files` al inicio, antes de `scrape_configs`:
```yaml
global:
  scrape_interval: 15s
rule_files:
  - "alert.rules.yml"
scrape_configs:
  - job_name: "node"
    static_configs:
      - targets: ["<IP_SERVIDOR>:9100"]
  - job_name: "kubernetes"
    static_configs:
      - targets: ["<IP_SERVIDOR>:10250"]
```

**Segundo, monta el archivo dentro del contenedor de Prometheus en `docker-compose.monitoring.yml`:**
```bash
nano docker-compose.monitoring.yml
```
Agrega el archivo al bloque `volumes` del servicio `prometheus`:
```yaml
services:
  prometheus:
    image: prom/prometheus
    volumes:
      - "./prometheus.yml:/etc/prometheus/prometheus.yml"
      - "./alert.rules.yml:/etc/prometheus/alert.rules.yml"
    ports: ["9090:9090"]
```
→ Sin este segundo cambio, `prometheus.yml` (dentro del contenedor) apuntaría a un `alert.rules.yml` que no existe en ese filesystem — el archivo vive en tu servidor, pero Prometheus corre dentro de un contenedor con su propio filesystem aislado, así que necesita este `volume` para verlo.

**3. Reinicia el stack para aplicar los cambios**

```bash
docker compose -f docker-compose.monitoring.yml up -d
```
→ Compose detecta los cambios en la configuración y recrea el contenedor de `prometheus` con los nuevos volúmenes montados.

**4. Verifica que las reglas se cargaron correctamente**

En el navegador:
```
http://<IP_SERVIDOR>:9090/rules
```
→ Debe listar las dos alertas (`DiscoLleno`, `CPUAlta`) bajo el grupo `node-alerts`, con estado `inactive` (normal si las condiciones no se están cumpliendo todavía) o `firing` (si sí se están cumpliendo).

**Fix si la página de `/rules` sale vacía:**
```bash
docker compose -f docker-compose.monitoring.yml logs prometheus | grep -i error
```
→ Busca errores de parseo YAML (mismo tipo de problema de indentación ya visto en `compose.yaml`) o de "file not found" si el volumen no quedó bien montado.

**5. Prueba una alerta disparándose de verdad**

Las alertas reales (`DiscoLleno` al 15%, `CPUAlta` al 85%) pueden tardar en cumplirse en un lab tranquilo — para *ver* el ciclo completo de una alerta sin esperar a que el disco casi se llene, agrega una temporalmente con un umbral ridículamente bajo, que case casi seguro:

```bash
nano alert.rules.yml
```
Agrega una tercera alerta de prueba al mismo grupo:
```yaml
groups:
  - name: node-alerts
    rules:
      - alert: DiscoLleno
        expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 < 15
        for: 5m
        labels: {severity: critical}
        annotations: {summary: "Disco con menos de 15% libre en {{ $labels.instance }}"}

      - alert: CPUAlta
        expr: 100 - (avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 85
        for: 10m
        labels: {severity: warning}

      - alert: PruebaSiempreActiva
        expr: up == 1
        for: 10s
        labels: {severity: info}
        annotations: {summary: "Alerta de prueba — se dispara siempre que el target esté UP"}
```
→ `up == 1` es una métrica interna de Prometheus que vale `1` mientras el target esté siendo scrapeado correctamente (`node_exporter` respondiendo) — casi siempre es cierto en un lab activo, así que esta alerta se dispara de forma predecible. `for: 10s` (en vez de minutos) hace que pase a `firing` casi de inmediato, en vez de esperar.

**Aplica el cambio:**
```bash
docker compose -f docker-compose.monitoring.yml up -d
```
→ Recuerda: recrea el contenedor de Prometheus para que recargue el archivo montado.

**Obsérvala pasar por los tres estados, en vivo:**
```
http://<IP_SERVIDOR>:9090/alerts
```
→ (Nota: es `/alerts`, distinto de `/rules` del paso 4 — `/rules` muestra las reglas *definidas*, `/alerts` muestra su *estado actual* de evaluación). Recarga la página cada pocos segundos y verás `PruebaSiempreActiva` avanzar:
1. **`inactive`** (gris) — la condición (`up == 1`) aún no se evaluó como verdadera, o recién empezó a cumplirse y no ha pasado el tiempo de `for:`.
2. **`pending`** (amarillo) — la condición ya es verdadera, pero todavía no pasaron los `10s` de `for:` — Prometheus espera para confirmar que no es un pico momentáneo (mismo concepto que ya viste con `for: 5m` en `DiscoLleno`).
3. **`firing`** (rojo) — pasaron los `10s` con la condición sostenida; la alerta está activa de verdad.

**Por qué la alerta de `alert.rules.yml` no aparece en `Grafana → Alerting → Alert rules`**

Esto es esperado, no un error: por defecto, la sección **Alert rules** de Grafana solo lista alertas **creadas dentro de Grafana** (llamadas "Grafana-managed"). Las reglas que definiste en `alert.rules.yml` viven y se evalúan **dentro de Prometheus** — Grafana solo las mostraría ahí si configuras esa fuente de datos específicamente como "fuente externa de alertas" (Mimir/Loki/Prometheus Alerting), un paso adicional que no cubrimos en la sección 7.2. Para visualizar una alerta en la UI de Grafana de forma directa, lo más simple es crear una **regla de alerta nativa de Grafana** que consulte Prometheus — que es justo lo que ya haces al usarlo como fuente de datos.

**Crea un Grafana Alert Rule, paso a paso:**

**1. Ve a la sección de alertas de Grafana**
```
Menú lateral → Alerting → Alert rules → New alert rule
```

**2. Define la consulta (Query)**
- En **"1. Define query"**, selecciona la fuente de datos **Prometheus** que ya configuraste (sección 7.2, paso 5).
- En el campo de consulta, escribe la misma métrica de prueba usada en `alert.rules.yml`:
  ```
  up
  ```
  → Simple y siempre tiene datos si `node_exporter` está siendo scrapeado.

**3. Define la condición (Condition)**
- En **"2. Define alert condition"**, Grafana agrega automáticamente un paso `Reduce` (resume la serie de tiempo a un solo valor, ej. `Last`) y un paso `Threshold`.
- Configura el threshold como: **`IS BELOW 1`** — así se dispara cuando `up` deja de ser `1` (el target deja de responder), o para forzar que se dispare siempre en la prueba, usa **`IS ABOVE 0`** (si `up` vale `1`, siempre es mayor que `0` — dispara de inmediato, igual que hiciste con `up == 1` en Prometheus).

**4. Configura cada cuánto se evalúa**
- En **"3. Add folder and labels"**, crea o selecciona una carpeta (ej. "Homelab").
- En **"4. Set evaluation behavior"**:
  - Evaluation group: crea uno nuevo, ej. `node-checks`, con intervalo de evaluación `10s` (mismo espíritu que el `for: 10s` de la prueba en Prometheus).
  - **Pending period**: `0s` para que pase a `Firing` casi de inmediato en esta prueba (en una alerta real, dejarías unos minutos, igual que `for: 5m`/`10m` en `alert.rules.yml`).

**5. Guarda la regla**
```
Save rule and exit
```

**6. Visualízala pasando por sus estados**
```
Grafana → Alerting → Alert rules
```
→ Ahora sí verás tu regla listada, con su estado actual:
- **`Normal`** (verde) — la condición no se cumple.
- **`Pending`** (amarillo) — la condición se cumple, esperando el `pending period`.
- **`Firing`** (rojo) — alerta activa.

Haz clic sobre la regla para ver el historial de transiciones de estado y el valor exacto evaluado en cada ciclo.

**7. (Opcional) Agrégala a un dashboard**

Puedes agregar un panel de tipo "Alert list" a cualquier dashboard (incluido el 1860 que ya importaste) para ver el estado de tus alertas junto a las demás métricas:
```
Dashboard → Add → Visualization → tipo de panel: "Alert list"
```

**8. Limpieza — borra la regla de prueba cuando termines**
```
Grafana → Alerting → Alert rules → (selecciona la regla) → Delete
```

**6. Quita la alerta de prueba en Prometheus una vez que confirmaste el ciclo completo**

```bash
nano alert.rules.yml
```
→ Borra el bloque de `PruebaSiempreActiva` (no tiene valor real en producción, solo era para verificar que el mecanismo de alertas funciona de punta a punta) y vuelve a aplicar:
```bash
docker compose -f docker-compose.monitoring.yml up -d
```

## FASE 8 — Automatización: script de arranque único

Después de varias fases, reiniciar todo el homelab significa recordar comandos distintos para Docker, k3s, y cada stack de Compose por separado. Este script los consolida en uno solo.

**Crea el script:**
````bash
nano /opt/scripts/start-lab.sh
````

````bash
#!/usr/bin/env bash
# start-lab.sh — Levanta todo el homelab SRE con un solo comando
set -uo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[FAIL]${NC} $1"; }

export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"

echo "=== Levantando homelab SRE ==="
for svc in docker k3s node_exporter; do
  systemctl is-active --quiet "$svc" && log "$svc activo" || { warn "$svc inactivo, iniciando..."; sudo systemctl start "$svc" 2>/dev/null && log "$svc iniciado" || err "$svc no pudo iniciar"; }
done

MONITORING_DIR="/opt/monitoring"
[ -f "$MONITORING_DIR/docker-compose.monitoring.yml" ] && (cd "$MONITORING_DIR" && docker compose -f docker-compose.monitoring.yml up -d && log "Monitoreo levantado") || warn "Monitoreo omitido"

for dir in /opt/apps/compose-lab /opt/apps/db-stack; do
  { [ -f "$dir/compose.yaml" ] || [ -f "$dir/docker-compose.yml" ]; } && (cd "$dir" && docker compose up -d && log "Proyecto levantado: $dir")
done

if command -v kubectl &> /dev/null && [ -f "/opt/k8s/deployment.yaml" ]; then
  kubectl apply -f /opt/k8s/deployment.yaml && log "Manifiesto k8s aplicado" || err "Falló apply de k8s"
fi

echo "=== Resumen ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
command -v kubectl &> /dev/null && kubectl get pods
IP=$(hostname -I | awk '{print $1}')
echo "Prometheus: http://${IP}:9090 | Grafana: http://${IP}:3000"
````
→ `export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"` asegura que el script encuentre el kubeconfig aunque corra fuera de tu sesión interactiva normal.

**Dale permisos y valida sintaxis antes de ejecutar:**
````bash
chmod +x /opt/scripts/start-lab.sh
bash -n /opt/scripts/start-lab.sh
````

**Ejecuta:**
````bash
/opt/scripts/start-lab.sh
````

**Fix si la sección de Kubernetes falla con HTML de error en vez de un error real**: ver el Incidente #22 en [incidentes-sre.md](./incidentes-sre.md) — casi siempre significa que `~/.kube/config` no existe; créalo con `mkdir -p ~/.kube && sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config && sudo chown $(id -u):$(id -g) ~/.kube/config`.


---

## Checklist final de validación

```bash
sudo ufw status verbose          # firewall activo y reglas correctas
sudo systemctl status fail2ban   # protección brute-force activa
sudo systemctl status docker     # docker corriendo
kubectl get nodes                # cluster k3s "Ready"
docker ps                        # contenedores esperados corriendo
curl localhost:9090/-/healthy    # Prometheus OK
curl localhost:9100/metrics | head -5  # node_exporter emitiendo datos
```
→ Ejecuta este bloque completo después de cualquier cambio mayor. Si algo falla, es tu primer punto de diagnóstico.

---

## Próximos pasos sugeridos (fuera de este playbook)
- CI/CD (GitHub Actions/GitLab CI) para build+push+deploy automático
- Alertmanager → Slack/PagerDuty para notificaciones reales
- Backups automatizados con `restic` o `velero` (para k8s)
- TLS con Let's Encrypt (`certbot` o `cert-manager` en k8s)

---

## Guía: publicar este proyecto en GitHub como portfolio

El objetivo no es solo subir archivos — es que un reclutador o hiring manager entienda tu nivel en 30 segundos de scroll. Estructura y pasos:

### 1. Estructura de carpetas recomendada

```bash
mkdir -p sre-homelab-portfolio/{scripts,ansible,k8s,monitoring,docs}
cd sre-homelab-portfolio
```
```
sre-homelab-portfolio/
├── README.md                 ← lo más importante del repo
├── incidentes-sre.md         ← tu bitácora de errores, referenciada desde el playbook
├── scripts/                  ← tus .sh y .py (backup.sh, healthcheck.py)
├── ansible/
│   ├── inventory.ini
│   └── playbook.yml
├── k8s/
│   ├── deployment.yaml
│   └── service.yaml
└── monitoring/
    ├── docker-compose.monitoring.yml
    ├── prometheus.yml
    └── alert.rules.yml
```
→ Un repo organizado por dominio (no todo suelto en la raíz) es la primera señal de seniority que ve un evaluador.

### 2. Inicializar el repositorio

```bash
cd sre-homelab-portfolio
git init
git config user.name "Tu Nombre"
git config user.email "tu@email.com"
```
→ `git init` crea el repositorio local. El `config` identifica tus commits (obligatorio la primera vez en un servidor nuevo).

### 3. `.gitignore` — crítico antes del primer commit

```bash
cat > .gitignore << 'EOF'
*.log
.env
secrets.yml
*.tar.gz
__pycache__/
*.pyc
.venv/
kubeconfig
EOF
```
→ **Nunca subas secretos, logs, o archivos binarios generados.** Un `.env` o `kubeconfig` filtrado en GitHub es un incidente de seguridad real, no un error cosmético.

### 4. Escribir el README (esto es lo que realmente te evalúan)

```bash
nano README.md
```

Estructura mínima que debe tener:

```markdown
# SRE Homelab — Ubuntu + Docker + K8s + Ansible + Monitoring

Proyecto de laboratorio personal implementando un stack SRE completo
desde cero: hardening de servidor, contenedores, orquestación,
automatización de infraestructura y observabilidad.

## Stack
- Ubuntu Server 22.04/24.04
- Bash + Python (automatización)
- Docker / Docker Compose
- Kubernetes (k3s)
- Ansible (IaC)
- Prometheus + Grafana + node_exporter

## Arquitectura
[diagrama o descripción de cómo se conectan las piezas]

## Cómo ejecutar
```bash
git clone https://github.com/tuusuario/sre-homelab-portfolio
cd sre-homelab-portfolio
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml --check
```

## Incidentes documentados
Ver [incidentes-sre.md](incidentes-sre.md) — bitácora real de errores
encontrados y su resolución durante la implementación.

## Qué aprendí
[2-3 líneas de aprendizajes técnicos concretos, no genéricos]
```
→ **Por qué la sección "Incidentes documentados" importa tanto**: cualquiera puede copiar comandos de un tutorial. Documentar errores reales y cómo los diagnosticaste demuestra troubleshooting — que es literalmente el trabajo de un SRE. Es tu diferenciador más fuerte en un portfolio junior.

### 5. Primer commit

```bash
git add .
git status
```
→ **Siempre** revisa `git status` antes de `commit` — confirma que no se coló ningún secreto o archivo generado que el `.gitignore` debió excluir.

```bash
git commit -m "Initial commit: estructura base del homelab SRE"
```

### 6. Crear el repo en GitHub y subirlo

```bash
gh auth login
gh repo create sre-homelab-portfolio --public --source=. --remote=origin
```
→ `gh` es la CLI oficial de GitHub (`sudo apt install gh` si no la tienes). Crea el repo remoto y lo enlaza en un solo paso. Alternativa sin `gh`: crear el repo manualmente en github.com y luego:
```bash
git remote add origin https://github.com/tuusuario/sre-homelab-portfolio.git
```

```bash
git branch -M main
git push -u origin main
```
→ `-u` fija `origin main` como destino por defecto, para que luego solo uses `git push`.

### 7. Pulido final (lo que separa un repo "junior" de uno "portfolio-ready")

- **Topics/tags en GitHub**: agrega `sre`, `devops`, `ansible`, `kubernetes`, `docker` en la configuración del repo (mejora descubribilidad).
- **LICENSE**: agrega una licencia MIT (`gh repo edit --add-license mit` o desde la UI) — muestra profesionalismo.
- **Commits incrementales, no uno solo gigante**: si sigues trabajando, haz commits por fase (`feat: agrega monitoreo con Prometheus`) — un historial de commits legible demuestra forma de trabajar, no solo el resultado final.
- **Diagrama de arquitectura**: una imagen simple (puedes hacerla en [draw.io](https://draw.io) o con Mermaid directo en el README) vale más que párrafos de texto.
- **Nunca subas IPs reales, dominios reales, ni credenciales** — usa placeholders (`<IP_SERVIDOR>`) como en este mismo playbook.

```bash
git add incidentes-sre.md
git commit -m "docs: agrega bitácora de incidentes (14 casos, FASE 2-4)"
git push
```
→ Así es como se ve, en la práctica, ir documentando tu aprendizaje como historial de commits real.
