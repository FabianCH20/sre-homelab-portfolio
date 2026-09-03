# Bitácora de Incidentes — SRE Homelab
🇬🇧 [Read in English](incidents-sre-eng.md)
> Errores reales encontrados practicando el [playbook principal](./playbook-sre-ubuntu-server.md), documentados en formato síntoma → causa raíz → diagnóstico → fix → lección. En SRE esto se llama **runbook de incidentes**: el objetivo es no repetir la misma investigación dos veces, y demostrar troubleshooting real, no solo copiar comandos de un tutorial. Cada incidente incluye referencias a documentación oficial y del repositorio GitHub de la herramienta involucrada, para profundizar más allá del fix puntual.

---

## FASE 2 — Bash

**Incidente #1 — `Permission denied` al guardar el script con `nano`**

- **Síntoma**: `nano` no permite guardar el archivo en `/opt/scripts/backup.sh`.
- **Causa raíz**: `/opt/scripts` pertenece a `root` por defecto; el usuario normal no tiene permiso de escritura ahí.
- **Diagnóstico**:
  ```bash
  ls -ld /opt/scripts
  ```
- **Fix aplicado**:
  ```bash
  sudo chown -R $USER:$USER /opt/scripts
  ```
  → Alternativa puntual: `sudo nano /opt/scripts/backup.sh` (pero deja el archivo con dueño `root`, generando el mismo problema después).
- **Lección**: antes de trabajar en un directorio del sistema (`/opt`, `/etc`, `/var`), verificar dueño con `ls -ld` primero, no asumir permisos.
- **Referencias**: Oficial — [GNU Coreutils Manual: chown/chmod](https://www.gnu.org/software/coreutils/manual/html_node/File-permissions.html) · GitHub — [man-pages (chown(1), ls(1))](https://github.com/mkerrisk/man-pages)

---

**Incidente #2 — `unexpected EOF while looking for matching` al ejecutar el bloque `if`**

- **Síntoma**: bash lanza error de sintaxis y no ejecuta el script.
- **Causa raíz**: el bloque `if`/`fi` quedó incompleto al copiar y pegar — faltaba el `fi` de cierre, o una comilla se convirtió en comilla "curva" (`"`) por venir de un editor de texto enriquecido en vez de texto plano.
- **Diagnóstico**:
  ```bash
  cat -A backup.sh      # revisa caracteres invisibles/raros
  bash -n backup.sh     # valida sintaxis sin ejecutar
  ```
- **Fix aplicado**: reescribir el bloque directamente en `nano` en vez de pegarlo, asegurando el `fi` de cierre y comillas rectas (`"`, no `"`/`"`).
- **Lección**: **siempre correr `bash -n script.sh` antes de `./script.sh`** — detecta errores de sintaxis sin efectos secundarios.
- **Referencias**: Oficial — [GNU Bash Reference Manual: Conditional Constructs](https://www.gnu.org/software/bash/manual/html_node/Conditional-Constructs.html) · GitHub — [ShellCheck Wiki](https://github.com/koalaman/shellcheck/wiki)

---

**Incidente #3 — `tar`: `Cannot stat: no such file or directory` + `Permission denied` + mensaje de éxito falso**

- **Síntoma**:
  ```
  tar: /etc/nginx: Cannot stat: no such file or directory
  tar (child): /var/backups/backup.tar.gz: Cannot open: Permission denied
  backup completado
  ```
- **Causa raíz** (dos problemas simultáneos):
  1. `/etc/nginx` no existía porque nginx no estaba instalado — la ruta del ejemplo no aplicaba a este servidor.
  2. `/var/backups` pertenece a `root`; sin permisos de escritura, `tar` no pudo crear el archivo destino.
  3. **Problema silencioso más grave**: el script imprimió `"Backup completado"` a pesar de que `tar` falló — porque no tenía `set -euo pipefail`, así que bash siguió ejecutando después del error.
- **Diagnóstico**:
  ```bash
  ls /etc/nginx           # confirma si la ruta origen existe
  ls -ld /var/backups     # confirma dueño del directorio destino
  ```
- **Fix aplicado**:
  ```bash
  sudo chown -R $USER:$USER /var/backups
  ```
  y cambio de ruta de origen a una que sí existiera (`/etc/hostname`), más agregar `set -euo pipefail` al inicio del script para que se detenga en el primer fallo real en vez de continuar y reportar éxito falso.
- **Lección**: un script sin `set -euo pipefail` puede fallar silenciosamente y reportar éxito. Esta cabecera no es opcional en scripts de producción — es la diferencia entre un fallo visible y un backup corrupto que nadie detecta hasta que se necesita restaurar.
- **Referencias**: Oficial — [GNU Bash Manual: The Set Builtin](https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html) · GitHub — [ShellCheck Wiki: SC2312 (set -e pitfalls)](https://github.com/koalaman/shellcheck/wiki/SC2312)

---

**Incidente #4 — `syntax error near unexpected token '('` al usar `exec > >(tee -a "$LOGFILE") 2>&1`**

- **Síntoma**:
  ```
  syntax error near unexpected token `('
  ```
- **Causa raíz**: el script se ejecutó con `sh backup.sh` en vez de `bash backup.sh` (o `./backup.sh`). En Ubuntu, `sh` es en realidad `dash`, un shell más simple que **no soporta** *process substitution* (`>(...)` / `<(...)`) — sintaxis exclusiva de bash usada en `exec > >(tee -a "$LOGFILE") 2>&1`.
- **Diagnóstico**:
  ```bash
  head -1 backup.sh   # confirma que el shebang sea #!/usr/bin/env bash
  ```
  → Si el shebang está correcto pero el error persiste, el problema es cómo se invocó el script (con `sh` explícito), no el archivo en sí.
- **Fix aplicado**: ejecutar con `bash backup.sh` o `./backup.sh` (nunca `sh backup.sh`) cuando el script usa sintaxis específica de bash.
- **Lección**: el shebang (`#!/usr/bin/env bash`) solo se respeta si ejecutas el script como `./script.sh`. Si alguien más (o un cron, un CI) lo invoca con `sh script.sh`, el shebang se ignora y el shell usado es `dash` — mucho más limitado.
- **Referencias**: Oficial — [GNU Bash Manual: Process Substitution](https://www.gnu.org/software/bash/manual/html_node/Process-Substitution.html) · GitHub — [ShellCheck Wiki: SC2039 (bashisms usados con sh/dash)](https://github.com/koalaman/shellcheck/wiki/SC2039)

---

**Incidente #5 — `syntax error near unexpected token '('` con `bash` correcto — espacio mal ubicado**

- **Síntoma**: mismo mensaje de error que el Incidente #4, pero esta vez ejecutando ya correctamente con `bash`.
  ```
  backup.sh: line 5: syntax error near unexpected token `('
  ```
- **Causa raíz**: la línea 5 tenía un espacio corrido:
  ```bash
  exec >> (tee -a "$LOGFILE") 2>&1     # ❌ incorrecto
  ```
  en vez de:
  ```bash
  exec > >(tee -a "$LOGFILE") 2>&1     # ✅ correcto
  ```
  `>> (...)` se interpreta como redirección de append (`>>`) seguida de un subshell suelto — sintaxis inválida ahí. `> >(...)` es *process substitution*: un `>` de redirección normal seguido de `>(...)`, sin espacio entre `>` y `(`.
- **Diagnóstico**:
  ```bash
  sed -n '5p' backup.sh       # imprime solo la línea 5 para inspección
  cat -A backup.sh | sed -n '5p'   # revisa caracteres invisibles
  bash -n backup.sh           # valida sintaxis sin ejecutar
  ```
- **Fix aplicado**: corregir la línea a `exec > >(tee -a "$LOGFILE") 2>&1`, sin espacio entre el `>` y el `>(`.
- **Lección**: en sintaxis de bash, la posición exacta de los espacios en operadores de redirección cambia el significado por completo (`>>` append vs `> >(` process substitution). Un solo carácter desplazado produce un error de sintaxis que no dice "tienes un espacio de más" — hay que inspeccionar la línea exacta con `sed -n 'Np'` para detectarlo.
- **Referencias**: Oficial — [GNU Bash Manual: Redirections](https://www.gnu.org/software/bash/manual/html_node/Redirections.html) · GitHub — [ShellCheck Wiki (índice de reglas)](https://github.com/koalaman/shellcheck/wiki/Checks)

---

**Incidente #6 — `Permission denied` en `/var/log/chrony`, `/var/log/private`, etc. al comprimir logs**

- **Síntoma**:
  ```
  gzip: /var/log/landscape/sysinfo.log.gz: Permission denied
  find: '/var/log/chrony': Permission denied
  gzip: /var/log/bootstrap.log.gz: Permission denied
  find: '/var/log/private': Permission denied
  ```
- **Causa raíz**: `/var/log` contiene subdirectorios de servicios del sistema (`chrony`, `landscape`, `private`, etc.) que pertenecen a `root` o a usuarios de sistema específicos. La línea del script:
  ```bash
  find /var/log -name "*.log" -mtime +30 -exec gzip {} \;
  ```
  no tenía privilegios para escribir/comprimir ahí. Ejecutar `sudo bash backup.sh` "resolvía" el síntoma pero elevaba **todo el script** innecesariamente — mala práctica, ya que otras líneas del script no necesitan root.
- **Diagnóstico**:
  ```bash
  ls -ld /var/log/chrony /var/log/private   # confirma dueño real de esos directorios
  grep -n "find /var/log" backup.sh          # confirma si la línea tiene sudo o no
  ```
- **Fix aplicado — sudo quirúrgico**: en vez de anteponer `sudo` a la invocación completa del script, se agregó `sudo` únicamente a la línea que lo necesita:
  ```bash
  sudo find /var/log -name "*.log" -mtime +30 -exec gzip {} \;
  ```
  El resto del script sigue corriendo con el usuario normal.
- **Lección**: cuando solo una parte de un script necesita privilegios elevados, el `sudo` debe aplicarse a esa línea específica, no a la ejecución completa del script — principio de menor privilegio aplicado a nivel de línea, no solo de usuario.
- **Referencias**: Oficial — [sudoers(5) Manual (sudo.ws)](https://www.sudo.ws/docs/man/sudoers.man/) · GitHub — [sudo-project/sudo](https://github.com/sudo-project/sudo)

---

## FASE 3 — Python

**Incidente #7 — `SyntaxError: expected ':'` en la definición de `check_endpoint`**

- **Síntoma**:
  ```
  File "/opt/scripts/healtcheck.py", line 7
  def check_endpoint(url: str, timeout: int = 5) -> bool;
  SyntaxError: expected ':'
  ```
- **Causa raíz**: se usó `;` (punto y coma) en vez de `:` (dos puntos) al final de la definición de la función. En Python, `:` es lo que abre el bloque de código de una función, `if`, `for`, `class`, etc. — equivalente al `{` de otros lenguajes.
- **Diagnóstico**:
  ```bash
  python3 -m py_compile /opt/scripts/healtcheck.py   # valida sintaxis sin ejecutar
  ```
- **Fix aplicado**: cambiar `def check_endpoint(...) -> bool;` por `def check_endpoint(...) -> bool:`.
- **Nota adicional**: el archivo tenía un typo en el nombre (`healtcheck.py` en vez de `healthcheck.py`) — se corrigió con `mv` para que coincidiera con las referencias usadas en cron/systemd más adelante en el playbook.
- **Lección**: `python3 -m py_compile archivo.py` es el equivalente de `bash -n script.sh` — valida sintaxis sin efectos secundarios.
- **Referencias**: Oficial — [Python Language Reference: Compound Statements](https://docs.python.org/3/reference/compound_stmts.html) · GitHub — [python/cpython](https://github.com/python/cpython)

---

**Incidente #8 — `SyntaxError` en `if__name= "__main__":`**

- **Síntoma**:
  ```
  line 16
  if__name= "__main__":
  ```
- **Causa raíz**: dos errores combinados en la misma línea:
  1. Faltaba el espacio entre `if` y `__name__`, por lo que Python interpretaba `if__name` como un identificador único en vez de la palabra clave `if` seguida de la variable `__name__`.
  2. Faltaba un guion bajo (`__name__` tiene doble guion bajo antes y después) y se usó `=` (asignación) en vez de `==` (comparación).
- **Diagnóstico**:
  ```bash
  python3 -m py_compile /opt/scripts/healthcheck.py
  ```
- **Fix aplicado**: corregir a la forma estándar: `if __name__ == "__main__":`.
- **Lección**: `__name__` es una variable especial que Python define en todo módulo (vale `"__main__"` solo si el archivo se ejecuta directamente, no si se importa). Al retipear código a mano, es fácil perder un guion bajo o juntarlos mal — mejor copiar el código directo que reescribirlo de memoria.
- **Referencias**: Oficial — [Python Docs: `__main__` — Top-level script environment](https://docs.python.org/3/library/__main__.html) · GitHub — [python/cpython](https://github.com/python/cpython)

---

**Incidente #9 — `error: externally-managed-environment` al correr `pip install requests`**

- **Síntoma**:
  ```
  error: externally-managed-environment
  This environment is externally managed
  To install Python packages system-wide, try apt install python3-xyz
  ```
- **Causa raíz**: `pip install requests` se ejecutó **sin activar el venv primero**, así que apuntaba al Python del sistema. Ubuntu 23.04+/24.04 bloquea instalar paquetes con `pip` directo al sistema (PEP 668).
- **Diagnóstico**:
  ```bash
  which pip   # debe mostrar /opt/venvs/ops/bin/pip si el venv está activo
  ```
- **Fix aplicado**:
  ```bash
  source /opt/venvs/ops/bin/activate
  pip install requests
  ```
- **Lección**: el prompt de la terminal muestra un prefijo como `(ops)` cuando el venv está activo — señal visual rápida para confirmar en qué entorno estás instalando.
- **Referencias**: Oficial — [PEP 668 – Marking Python base environments as “externally managed”](https://peps.python.org/pep-0668/) · GitHub — [pypa/pip issue #11530 (origen de este mensaje)](https://github.com/pypa/pip/issues/11530)

---

**Incidente #10 — `PermissionError: [Errno 13] Permission denied` en `site-packages` al instalar dentro del venv activado**

- **Síntoma**:
  ```
  ERROR: Could not install packages due to an OSError: [Errno 13] Permission denied:
  '/opt/venvs/ops/lib/python3.14/site-packages/urllib3'
  ```
- **Causa raíz**: el venv se había creado originalmente con `sudo` (o dentro de un `/opt` cuyo dueño era `root`), así que aunque el venv estaba correctamente activado esta vez, el usuario normal no tenía permiso de escritura sobre `site-packages` — mismo patrón de fondo que el Incidente #1, pero afectando al venv completo.
- **Diagnóstico**:
  ```bash
  ls -ld /opt/venvs/ops
  ls -la /opt/venvs/ops/lib/python3.14/site-packages/ | head
  ```
- **Fix aplicado**:
  ```bash
  sudo chown -R $USER:$USER /opt/venvs/ops
  ```
  → Alternativa más limpia: dar `chown` al directorio padre (`/opt/venvs`) una sola vez, y crear el venv después SIN sudo.
- **Lección**: los problemas de permisos en `/opt` son recurrentes en este playbook porque `/opt` pertenece a `root` por defecto. Patrón que se repite: **verificar dueño con `ls -ld` antes de crear o escribir algo ahí**.
- **Referencias**: Oficial — [Python Docs: venv — Creation of virtual environments](https://docs.python.org/3/library/venv.html) · GitHub — [python/cpython (Lib/venv)](https://github.com/python/cpython/tree/main/Lib/venv)

---

**Incidente #11 — `bad minute` / `errors in crontab file, can't install` al cargar un cronjob desde archivo**

- **Síntoma**:
  ```
  "/opt/scripts/cron/healthcheck.cron":2 bad minute
  errors in crontab file, can't install
  ```
- **Causa raíz** (dos problemas combinados en el archivo `.cron`):
  1. El cronjob quedó **partido en dos líneas** en vez de una sola — cron requiere que todo el comando esté en una única línea. El mensaje "bad minute" era síntoma de esa ruptura, no de un carácter inválido en el campo de minuto en sí.
  2. El comando `crontab /opt/scripts/cron/healthcheck.cron` (usado desde la terminal para *cargar* el archivo) había quedado pegado por accidente **dentro** del propio archivo `.cron`, como una línea más.
- **Diagnóstico**:
  ```bash
  cat -n /opt/scripts/cron/healthcheck.cron   # numera líneas, revela la ruptura y la línea de más
  file /opt/scripts/cron/healthcheck.cron      # descarta problema de CRLF/saltos de línea
  cat -A ... | sed -n '2p'                     # descarta caracteres invisibles en la línea específica
  ```
- **Fix aplicado**: reescribir el archivo completo con el cronjob en una sola línea y sin el comando `crontab ...` pegado dentro.
- **Lección**: cuando un mensaje de error de cron señala un campo específico pero el campo se ve correcto a simple vista, revisar el archivo **completo** con números de línea (`cat -n`) antes de enfocarse solo en la línea señalada.
- **Referencias**: Oficial — [crontab(5) — Linux man-pages (man7.org)](https://man7.org/linux/man-pages/man5/crontab.5.html) · GitHub — [cronie-crond/cronie](https://github.com/cronie-crond/cronie)

---

## FASE 4 — Docker

**Incidente #12 — `permission denied` persistente al conectar al socket de Docker, incluso tras `newgrp docker`**

- **Síntoma**: `Permission denied while trying to connect to the Docker daemon socket at unix:///var/run/docker.sock`, y `newgrp docker` pedía contraseña y fallaba igual.
- **Causa raíz**: el `usermod -aG docker opsuser` original se había aplicado a un usuario (`opsuser`) distinto al que realmente se estaba usando en la sesión activa (otro usuario, ej. `ops` o el usuario real de conexión). El usuario en uso nunca fue agregado de verdad al grupo `docker` a nivel de sistema — por eso `newgrp` (que solo carga el grupo en la sesión, no lo asigna) fallaba pidiendo una contraseña de grupo que no existe.
- **Diagnóstico**:
  ```bash
  whoami
  groups $(whoami)
  getent group docker   # confirma qué usuarios pertenecen realmente al grupo
  ```
- **Fix aplicado**:
  ```bash
  sudo usermod -aG docker <usuario_real_en_uso>
  exit   # cerrar sesión completa — newgrp NO basta después de un usermod
  # volver a conectarse
  groups   # confirmar que "docker" ya aparece
  ```
- **Lección**: `newgrp` solo recarga los grupos ya asignados en la sesión actual; si el usuario nunca fue agregado al grupo a nivel de sistema, `newgrp` fallará pidiendo contraseña. Siempre confirmar `whoami` antes de diagnosticar problemas de grupo — es fácil perder de vista con qué usuario del sistema se está trabajando realmente, sobre todo si se alternó entre varios usuarios durante la sesión.
- **Referencias**: Oficial — [Docker Docs: Linux post-installation steps](https://docs.docker.com/engine/install/linux-postinstall/) · GitHub — [moby/moby](https://github.com/moby/moby)

---

**Incidente #13 — `Unable to locate package docker-compose-plugin` / `docker: 'compose' is not a docker command`**

- **Síntoma**:
  ```
  Error: Unable to locate package docker-compose-plugin
  ```
  y más adelante, al intentar usarlo:
  ```
  docker: 'compose' is not a docker command
  ```
- **Causa raíz**: el repositorio oficial de Docker (`download.docker.com`) no estaba registrado en las fuentes de `apt`. Esto ocurre cuando Docker se instaló por un medio que no configura ese repo (o el paso de configuración del repo falló silenciosamente), dejando `apt` sin forma de encontrar `docker-compose-plugin`, que no existe en los repositorios estándar de Ubuntu.
- **Diagnóstico**:
  ```bash
  ls /etc/apt/sources.list.d/docker.* 2>/dev/null || echo "No existe el repo de Docker"
  dpkg -l | grep docker   # confirma qué paquetes de Docker sí están instalados
  ```
- **Fix aplicado**: reinstalación limpia de Docker completa desde el repositorio oficial vía `apt` (ver sección de instalación desde cero del playbook principal), que registra el repo correctamente e instala `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin` y `docker-compose-plugin` juntos en un solo flujo — en vez de instalar Docker por un método y el plugin de Compose por separado con `apt install docker-compose-plugin` suelto, que fallaba porque el repo nunca quedó registrado.
- **Lección**: cuando falta un paquete específico de una herramienta que "debería venir junto" con otra ya instalada (como Compose con Docker), sospechar primero de que el repositorio de origen no está configurado, en vez de asumir que el nombre del paquete está mal escrito. `ls /etc/apt/sources.list.d/docker.*` es el primer lugar para confirmarlo (el archivo puede llamarse `docker.list` en el formato clásico o `docker.sources` en el formato deb822 actual).
- **Referencias**: Oficial — [Docker Docs: Install Docker Compose (Linux)](https://docs.docker.com/compose/install/linux/) · GitHub — [docker/compose](https://github.com/docker/compose)

---

**Incidente #14 — `-bash: EOF: Permission denied` al usar un heredoc (`<<EOF`) para registrar el repo de Docker**

- **Síntoma**:
  ```
  -bash: EOF: Permission denied
  ```
  al intentar crear `/etc/apt/sources.list.d/docker.sources` con un bloque `sudo tee ... <<EOF ... EOF`.
- **Causa raíz**: el heredoc se rompió a medio camino — la línea de cierre `EOF` no coincidió exactamente con lo que bash esperaba (espacios de más, salto de línea alterado al pegar el bloque). Cuando eso pasa, bash nunca reconoce el cierre del heredoc y termina interpretando la palabra suelta `EOF` como si fuera un comando a ejecutar — de ahí el `Permission denied`, probablemente por un archivo llamado `EOF` sin permiso de ejecución en el directorio actual.
- **Diagnóstico**: revisar si quedó un archivo `EOF` suelto en el directorio de trabajo, y confirmar el estado del archivo de destino a medio crear:
  ```bash
  ls -la EOF 2>/dev/null
  cat /etc/apt/sources.list.d/docker.sources 2>/dev/null
  ```
- **Fix aplicado**: limpiar los restos (`rm -f EOF`, borrar el archivo `.sources` incompleto) y volver a escribir el heredoc completo, asegurando que la línea de cierre `EOF` esté **completamente sola**, sin espacios antes ni después. Al escribir interactivamente en la terminal (en vez de pegar el bloque completo de golpe), el prompt cambia a `>` mientras el heredoc sigue abierto — eso confirma visualmente que aún no ha cerrado, y vuelve a `$` normal cuando sí cierra correctamente.
- **Lección**: los heredocs son frágiles al copiar/pegar bloques multilínea completos, porque cualquier alteración en la línea de cierre (aunque sea un espacio invisible) hace que bash nunca reconozca el fin del bloque. Para comandos de una sola línea con variables, la forma `echo "..." | sudo tee archivo` es menos propensa a este tipo de rupturas que un heredoc; para contenido multilínea real (como el formato `.sources`), el heredoc es necesario, pero conviene escribir al menos la línea de cierre a mano en vez de confiar en el pegado exacto.
- **Referencias**: Oficial — [GNU Bash Manual: Here Documents](https://www.gnu.org/software/bash/manual/html_node/Here-Documents.html) · GitHub — [ShellCheck Wiki](https://github.com/koalaman/shellcheck/wiki)

---

## FASE 5 — Kubernetes

**Incidente #15 — `bind: address already in use` al correr `kubectl port-forward`**

- **Síntoma**:
  ```
  Unable to listen on port 8080: Listeners failed to create with the following errors:
  [unable to create listener: Error listen tcp4 127.0.0.1:8080: bind: address already in use
   unable to create listener: Error listen tcp6 [::1]:8080: bind: address already in use]
  error: unable to listen on any of the requested ports: [{8080 8080}]
  ```
  al correr `kubectl port-forward miapp-7cd5b58c94-8lvpv 8080`.
- **Causa raíz** (dos problemas combinados):
  1. El comando se escribió con un solo número de puerto (`8080`) en vez del formato `<puerto-local>:<puerto-del-pod>`. Con un solo número, `kubectl` intenta usar ese mismo puerto tanto en el host como dentro del pod — pero el pod (`nginx:latest`) escucha en el puerto 80, no 8080, así que el formato correcto era `8080:80`.
  2. Aun corrigiendo el formato, el puerto local 8080 ya estaba **ocupado por otro proceso en el servidor** — el `bind: address already in use` es un conflicto de puerto a nivel de sistema operativo, sin relación con Kubernetes. Muy probablemente el contenedor `nginx-test` de Docker o el stack de WordPress (ambos usados en fases anteriores) seguían corriendo y mapeados también a 8080.
- **Diagnóstico**:
  ```bash
  sudo ss -tlnp | grep 8080   # confirma qué proceso ya escucha en ese puerto
  docker ps                    # revisa si un contenedor de Docker sigue mapeado a 8080
  ```
- **Fix aplicado**: usar un puerto local distinto para el `port-forward`, que no necesita coincidir con el puerto del pod:
  ```bash
  kubectl port-forward miapp-7cd5b58c94-8lvpv 8081:80
  curl http://localhost:8081
  ```
  → Alternativa: liberar el 8080 deteniendo el contenedor de Docker que lo estaba usando (`docker stop nginx-test`) antes de repetir el `port-forward` original.
- **Lección**: `kubectl port-forward` compite por puertos del host exactamente igual que cualquier otro proceso — no hay aislamiento especial solo por venir de Kubernetes. Antes de asumir que un puerto está libre, conviene revisar qué más quedó corriendo de fases o pruebas anteriores (Docker, Compose, etc.) en el mismo servidor.
- **Referencias**: Oficial — [Kubernetes Docs: kubectl port-forward reference](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#port-forward) · GitHub — [kubernetes/kubernetes](https://github.com/kubernetes/kubernetes) (instalación usada: [k3s-io/k3s](https://github.com/k3s-io/k3s))

---

## FASE 6 — Ansible

**Incidente #16 — `ansible-playbook` se queda colgado en `TASK [Gathering Facts]` sin avanzar**

- **Síntoma**: el comando `ansible-playbook -i inventory.ini playbook.yml --check` imprime `PLAY [web]` y `TASK [Gathering Facts]`, y se queda ahí indefinidamente sin error visible ni progreso.
- **Causa raíz**: con `ansible_connection=local`, la tarea `become: true` del playbook necesita elevar a `sudo` en la sesión actual. Si el usuario requiere contraseña para `sudo` (sin `NOPASSWD` configurado), Ansible queda esperando esa contraseña — pero el prompt no siempre se muestra visible en el modo normal, dando la impresión de que el comando está "colgado" sin más información.
- **Diagnóstico**:
  ```bash
  ansible-playbook -i inventory.ini playbook.yml --check -vvv
  ```
  → El modo verbose (`-vvv`) expone el punto exacto donde se traba, incluyendo si está esperando la contraseña de `sudo`.
- **Fix aplicado**: usar el flag que hace visible el prompt de contraseña:
  ```bash
  ansible-playbook -i inventory.ini playbook.yml --check --ask-become-pass
  ```
  → Con esto, Ansible muestra explícitamente `BECOME password:` y continúa normalmente tras ingresarla.
- **Lección**: cuando una tarea de Ansible usa `become: true` y el usuario no tiene `sudo` sin contraseña configurado, el comando necesita `--ask-become-pass` (o `--ask-become-pass` junto con `--ask-pass` si también aplica a la conexión) — de lo contrario, el comando parece congelado en vez de fallar con un error claro.
- **Referencias**: Oficial — [Ansible Docs: Understanding privilege escalation (become)](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_privilege_escalation.html) · GitHub — [ansible/ansible](https://github.com/ansible/ansible)

---

**Incidente #17 — `Could not find or access 'app.env.j2'` en la tarea del módulo `template`**

- **Síntoma**:
  ```
  Could not find or access 'app.env.j2'
  Searched in:
      /opt/ansible/templates/app.env.j2
      /opt/ansible/app.env.j2
  ```
  con `PLAY RECAP` mostrando `ok=4 changed=1 ... failed=1` — es decir, las tareas anteriores del playbook (actualizar paquetes, instalar Docker, activar el servicio) sí se ejecutaron correctamente; solo la última tarea (`Copiar configuración de la app`, que usa el módulo `template`) falló.
- **Causa raíz**: `app.env.j2` era un nombre de archivo de ejemplo en el playbook genérico — nunca se creó el archivo real. El módulo `template` de Ansible requiere que el archivo fuente exista físicamente en una carpeta `templates/` junto al playbook antes de poder copiarlo (con sustitución de variables Jinja2) al destino.
- **Diagnóstico**: el propio mensaje de error ya indica las rutas exactas donde Ansible buscó el archivo y no lo encontró — confirma que el problema es la ausencia del archivo, no un error de sintaxis del playbook (las tareas previas corrieron bien).
- **Fix aplicado**: crear el archivo de plantilla que faltaba:
  ```bash
  mkdir -p /opt/ansible/templates
  nano /opt/ansible/templates/app.env.j2
  ```
  con contenido usando sintaxis Jinja2 para variables dinámicas, ej.:
  ```
  APP_ENV=production
  APP_DEBUG=false
  DB_HOST={{ ansible_default_ipv4.address | default('localhost') }}
  ```
  Tras crear el archivo, `ansible-playbook -i inventory.ini playbook.yml --check --ask-become-pass` pasó sin error.
- **Lección**: el módulo `template` de Ansible busca el archivo fuente en una carpeta `templates/` relativa al playbook por convención — un playbook puede ser sintácticamente válido y ejecutar varias tareas con éxito, y aun así fallar en una tarea puntual simplemente porque un archivo de soporte referenciado nunca se creó. El `PLAY RECAP` (`ok=X changed=Y failed=Z`) es la forma rápida de confirmar cuánto del playbook sí se aplicó antes del punto de falla.
- **Referencias**: Oficial — [ansible.builtin.template module docs](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/template_module.html) · GitHub — [ansible/ansible](https://github.com/ansible/ansible)

---

**Incidente #18 — `Cannot create container when image is not specified!` en el handler `docker_container`**

- **Síntoma**:
  ```
  fatal: [srv-prod-01]: FAILED! => {
      "changed": false,
      "msg": "Cannot create container when image is not specified!"
  }
  PLAY RECAP: ok=5 changed=2 ... failed=1
  ```
- **Causa raíz**: el handler `reiniciar app` usaba el módulo `docker_container` con `name: miapp` y `restart: true`, pero **sin la clave `image:`**. Como el contenedor `miapp` no existía todavía (nunca se había creado con `docker run` ni con otra tarea de Ansible), el módulo intentó crearlo desde cero — y para crear un contenedor Docker se necesita saber qué imagen usar. El handler solo se disparó por primera vez porque la tarea `template` del Incidente #17 (recién resuelta) reportó un cambio real (`notify: reiniciar app`), activando el handler por primera vez en esta sesión.
- **Diagnóstico**: el `PLAY RECAP` (`ok=5 changed=2 ... failed=1`) confirmó que todas las tareas previas corrieron bien — el fallo estaba aislado en el handler, y el propio mensaje `msg` nombra la causa exacta.
- **Fix aplicado**: agregar la clave `image:` al handler:
  ```yaml
  handlers:
    - name: reiniciar app
      docker_container:
        name: miapp
        image: nginx:latest
        state: started
        restart: true
  ```
  → Se usó `nginx:latest` (imagen pública real ya usada en Docker y Kubernetes) en vez de `miapp:1.0`, que nunca fue construida — mismo patrón que el `ErrImagePull` visto en el Incidente #15 de Kubernetes.
- **Lección**: el módulo `docker_container` de Ansible necesita `image:` explícito para poder crear un contenedor que aún no existe — omitirla no falla en la validación de sintaxis del playbook, solo al momento de ejecutar la tarea real. Los handlers, al dispararse condicionalmente (solo si algo cambió), pueden ocultar errores de configuración durante varias corridas hasta que finalmente se activan por primera vez.
- **Referencias**: Oficial — [community.docker.docker_container module docs](https://docs.ansible.com/projects/ansible/latest/collections/community/docker/docker_container_module.html) · GitHub — [ansible-collections/community.docker](https://github.com/ansible-collections/community.docker)

---

**Incidente #19 — `Destination directory /opt/app does not exist` en la tarea del módulo `template`**

- **Síntoma**:
  ```
  fatal: [srv-prod-01]: FAILED! => {
      "changed": false,
      "msg": "Destination directory /opt/app does not exist"
  }
  PLAY RECAP: ok=4 changed=0 ... failed=1
  ```
- **Causa raíz**: la tarea `Copiar configuración de la app` usa `template` con `dest: /opt/app/.env`, pero el directorio `/opt/app` nunca fue creado. El módulo `template` de Ansible **no crea directorios intermedios automáticamente** — a diferencia de `mkdir -p` en bash, espera que el destino ya exista.
- **Diagnóstico**: el mensaje de error ya es explícito sobre la causa (`Destination directory ... does not exist`); no requirió diagnóstico adicional más allá de confirmar que, en efecto, `/opt/app` no existía.
- **Fix aplicado**: agregar una tarea `file` con `state: directory` antes de la tarea `template`:
  ```yaml
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
  ```
- **Lección**: a diferencia de módulos como `copy` o herramientas de shell con `-p` (crear padres automáticamente), el módulo `template` de Ansible es estricto sobre que el directorio destino ya exista. Es una buena práctica declarar explícitamente la creación de directorios con el módulo `file` (`state: directory`) como una tarea separada, antes de cualquier tarea que escriba archivos dentro de ellos — mantiene el playbook idempotente y explícito sobre el estado que espera encontrar.
- **Referencias**: Oficial — [ansible.builtin.file module docs](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/file_module.html) · GitHub — [ansible/ansible](https://github.com/ansible/ansible)

---

## FASE 7 — Monitoreo

**Incidente #20 — `node_exporter: command not found` tras una descarga aparentemente exitosa**

- **Síntoma**: `node_exporter --version` devuelve `command not found`, a pesar de haber corrido antes el bloque de descarga y extracción.
- **Causa raíz**: el intento anterior de descarga había fallado silenciosamente por un problema de fondo (ver Incidente previo de la URL de `node_exporter` con versión fija desactualizada, que descargaba una página HTML 404 en vez del `.tar.gz` real). En un reintento posterior, la descarga y el `tar xvf` sí se completaron con éxito — quedó la carpeta `node_exporter-1.12.1.linux-amd64/` con el binario adentro — pero el último paso, `sudo mv .../node_exporter /usr/local/bin/`, nunca llegó a ejecutarse en esa sesión. El binario existía en el servidor, solo que no en una ruta incluida en el `PATH`.
- **Diagnóstico**:
  ```bash
  ls -la ~ | grep node_exporter   # confirma si la carpeta extraída existe
  ls -l ~/node_exporter-1.12.1.linux-amd64/   # confirma que el binario está dentro
  ```
- **Fix aplicado**: mover el binario explícitamente con la ruta completa (evitando el comodín `node_exporter-*/`, más propenso a ambigüedad si quedan restos de intentos previos con distintas versiones en el mismo directorio):
  ```bash
  sudo mv ~/node_exporter-1.12.1.linux-amd64/node_exporter /usr/local/bin/
  node_exporter --version
  rm -rf ~/node_exporter-1.12.1.linux-amd64 ~/node_exporter-1.12.1.linux-amd64.tar.gz
  ```
- **Lección**: cuando un comando de instalación multi-paso se interrumpe (por otro error previo, o por cortar la sesión a medio camino), no asumir que "no funciona" en general — verificar paso por paso cuál de los pasos individuales sí se completó (`ls -la` para confirmar archivos/carpetas resultantes) antes de repetir la instalación completa desde cero. En este caso, solo faltaba un `mv`, no volver a descargar nada.
- **Referencias**: Oficial — [Prometheus Docs: Installation](https://prometheus.io/docs/prometheus/latest/installation/) · GitHub — [prometheus/node_exporter](https://github.com/prometheus/node_exporter)

---

**Incidente #21 — `go-yaml load error in parser: did not find expected key` al agregar un segundo volumen en `docker-compose.monitoring.yml`**

- **Síntoma**:
  ```
  go-yaml load error in parser (while parsing a block mapping) at L4.C5-L8.C6: did not find expected key
  ```
  al correr `docker compose -f docker-compose.monitoring.yml up -d`.
- **Causa raíz**: al editar el archivo para agregar la segunda línea del bloque `volumes:` del servicio `prometheus` (montando también `alert.rules.yml`, para la sección de alertas), la indentación quedó inconsistente entre esa lista y las claves siguientes (`ports:`, y el servicio `grafana:` debajo) — mismo tipo de ruptura ya vista antes en `compose.yaml` (Incidente previo con WordPress + MariaDB), pero esta vez en el archivo de monitoreo.
- **Diagnóstico**:
  ```bash
  cat -n docker-compose.monitoring.yml   # revisa la indentación línea por línea
  cat -A docker-compose.monitoring.yml | sed -n '1,10p'   # descarta tabs mezclados con espacios
  ```
- **Fix aplicado**: reescribir el archivo completo con indentación de 2 espacios consistente en todos los niveles, tecleando en vez de pegar de golpe:
  ```yaml
  services:
    prometheus:
      image: prom/prometheus
      volumes:
        - "./prometheus.yml:/etc/prometheus/prometheus.yml"
        - "./alert.rules.yml:/etc/prometheus/alert.rules.yml"
      ports: ["9090:9090"]
    grafana:
      image: grafana/grafana
      ports: ["3000:3000"]
      volumes: ["grafana-data:/var/lib/grafana"]
  volumes:
    grafana-data:
  ```
  y validar con `docker compose -f docker-compose.monitoring.yml config` antes de volver a intentar `up -d`.
- **Lección**: agregar una sola línea a un archivo YAML que ya funcionaba es un punto de fallo común — el nuevo contenido puede desalinear visualmente el resto del bloque sin que sea obvio a simple vista en el editor. Validar con `docker compose config` (o el equivalente de la herramienta) después de **cualquier** edición a un YAML existente, no solo al crearlo por primera vez, evita repetir el ciclo de prueba-error en `up -d`.
- **Referencias**: Oficial — [YAML Specification 1.2](https://yaml.org/spec/1.2.2/) · GitHub — [docker/compose](https://github.com/docker/compose)

---

## Patrones transversales (para tu README)

A través de los 21 incidentes, cinco causas raíz se repiten una y otra vez — vale la pena nombrarlas explícitamente en el portfolio como evidencia de aprendizaje real:

1. **Permisos en directorios del sistema** (`/opt`, `/var/log`) — porque pertenecen a `root` por defecto. Aparece en los Incidentes #1, #3, #6, #10. Lección transversal: verificar dueño con `ls -ld` **antes** de escribir, no después de fallar.
2. **Contexto de ejecución no verificado** (¿qué usuario? ¿qué shell? ¿venv activado? ¿repo registrado? ¿qué más está corriendo en el servidor? ¿sudo pide contraseña?) — antes de asumir que un comando "debería funcionar". Aparece en los Incidentes #4, #9, #12, #13, #15, #16. Lección transversal: confirmar el contexto exacto (`whoami`, `which`, `groups`, `ls /etc/.../docker.*`, `ss -tlnp`, modo `-vvv`) es más rápido que adivinar por el mensaje de error.
3. **Bloques multilínea rotos al copiar/pegar o editar** (`if`/`fi`, cronjobs, heredocs, YAML) — un carácter invisible o una línea de indentación mal formada produce errores de sintaxis confusos que no describen la causa real. Aparece en los Incidentes #2, #11, #14, #21. Lección transversal: cuando el error de sintaxis no tiene sentido a simple vista, revisar el archivo completo con `cat -n` o `cat -A`, no solo la línea que el mensaje señala — y validar con la herramienta de config-check correspondiente (`bash -n`, `docker compose config`, etc.) después de **cualquier** edición, no solo al crear el archivo.
4. **Módulos declarativos que asumen precondiciones no cumplidas** (imagen no especificada, directorio destino inexistente, archivo fuente no creado) — a diferencia de scripts imperativos, los módulos de Ansible fallan explícitamente en vez de improvisar un valor por defecto. Aparece en los Incidentes #17, #18, #19. Lección transversal: cada módulo declarativo (Ansible, Kubernetes, Compose) tiene sus propias precondiciones implícitas — leer la documentación oficial del módulo específico antes de asumir que el comportamiento será "como en bash".
5. **Instalaciones multi-paso interrumpidas a medio camino** — un paso previo falla (Incidente de URL desactualizada) y el flujo se retoma más tarde sin volver a verificar cuáles pasos sí se completaron. Aparece en el Incidente #20. Lección transversal: antes de repetir una instalación completa desde cero, verificar con `ls -la` qué artefactos ya existen — puede que solo falte el último paso, no todo el proceso.


