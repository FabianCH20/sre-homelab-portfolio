# SRE Playbook: Ubuntu Server From Scratch
🇪🇸 [Leer en español](playbook-sre-ubuntu-server.md)
> Format: `command → what it does → why / symptom it fixes`
> Level: Junior SRE. Run in order. Each phase assumes the previous one is complete.

---

## PHASE 1 — Base System Hardening

**Official references:**

- [Ubuntu Server: Security](https://documentation.ubuntu.com/server/how-to/security/) — official Ubuntu Server hardening guide
- [UFW — Official Ubuntu Wiki](https://help.ubuntu.com/community/UFW) · [Fail2ban Docs](https://fail2ban.readthedocs.io/)
- [github.com/fail2ban/fail2ban](https://github.com/fail2ban/fail2ban) — Fail2ban project repository

```bash
sudo apt update && sudo apt upgrade -y
```
→ `update` refreshes the package index, `upgrade` installs new versions. **Symptom it fixes**: known CVEs left unpatched.

```bash
sudo apt install -y ufw fail2ban unattended-upgrades curl wget git htop vim net-tools
```
→ Base tools: `ufw` (simple firewall), `fail2ban` (blocks brute-force IPs), `unattended-upgrades` (automatic security patches).

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 2222/tcp
sudo ufw enable
```
→ Firewall in "everything closed except what's explicit" mode. **Fix**: if you use a different SSH port, open it BEFORE `enable`.

```bash
sudo systemctl enable fail2ban --now
sudo fail2ban-client status sshd
```
→ Enables and verifies SSH brute-force protection.

```bash
sudo timedatectl set-timezone America/Costa_Rica
sudo timedatectl set-ntp true
```
→ Synced time is critical: misaligned logs = impossible debugging, TLS certificates fail with drift.

```bash
sudo hostnamectl set-hostname srv-prod-01
```
→ Names the host consistently with your inventory (useful later in Ansible).

---

## PHASE 2 — Bash: Operational Fundamentals

**Official references:**

- [GNU Bash Reference Manual](https://www.gnu.org/software/bash/manual/bash.html) — official Bash documentation
- [github.com/koalaman/shellcheck](https://github.com/koalaman/shellcheck) — static shell script linter, with a [rules wiki](https://github.com/koalaman/shellcheck/wiki) documenting common errors (recommended to run on any script before production)

### 2.1 — Create the file

```bash
mkdir -p /opt/scripts
cd /opt/scripts
nano backup.sh
```
→ `mkdir -p`: creates the directory if it doesn't exist (`-p` = doesn't fail if it already exists, and creates intermediate parents). Ops convention: keep your own scripts in `/opt/scripts`, not in `/home` or `/tmp` (lost on reboot in some setups). `nano` is the editor; you can use `vim` if you prefer.

Type this inside `nano`:
```bash
#!/usr/bin/env bash
echo "Hello, I'm a script"
```
→ Saving in nano: `Ctrl+O` (write out) → `Enter` → `Ctrl+X` (exit).

**What is the first line?**
```bash
#!/usr/bin/env bash
```
→ It's called a **shebang**. It tells the operating system which interpreter to use to run the file. Without this line, the system doesn't know if it's bash, python, etc., and treats the file as plain text. `env bash` (instead of a fixed `/bin/bash`) looks for bash in the system's `PATH` — more portable across distros.

### 2.2 — Grant execute permissions

```bash
ls -l backup.sh
```
→ You'll see something like `-rw-r--r--`. Those first 10 characters are permissions: the file does NOT have execute permission (there's no `x`).

```bash
chmod +x backup.sh
ls -l backup.sh
```
→ `chmod +x` adds execute permission. Now you'll see `-rwxr--r--` (the `x` appeared). **Symptom it fixes**: `Permission denied` error when trying to run the script.

Breakdown of `-rwxr--r--` permissions:
```
- rwx r-- r--
| |   |   └─ others: read only
| |   └───── group: read only
| └───────── owner: read, write, execute
└─────────── file type (- = regular file, d = directory)
```

### 2.3 — Run the script

```bash
./backup.sh
```
→ The `./` is mandatory if the current directory isn't in your `PATH` (normally it isn't, for security — it prevents a malicious file named `ls` in your current folder from running instead of the real system `ls`).

```bash
bash backup.sh
```
→ An alternative that **doesn't require** `chmod +x`, because you're explicitly telling bash to interpret it. Useful for quick tests, but in production use `./script.sh` with correct permissions and a shebang — that's the standard.

### 2.4 — Variables and arguments

```bash
#!/usr/bin/env bash
NAME="server-01"
echo "Backup of: $NAME"
```
→ Variables with no spaces around the `=` (`NAME = "x"` is a common syntax error). They're read with `$NAME` or `${NAME}`.

```bash
#!/usr/bin/env bash
echo "Script run: $0"
echo "First argument: $1"
echo "Total arguments: $#"
```
```bash
./backup.sh production
```
→ `$0` = script name, `$1` = first argument passed (`production`), `$#` = number of arguments. This is how scripts receive parameters instead of having hardcoded values.

### 2.5 — Conditionals and flow control

```bash
#!/usr/bin/env bash
if [ -d "/var/backups" ]; then
  echo "The directory exists"
else
  mkdir -p /var/backups
  echo "Directory created"
fi
```
→ `-d` tests whether it's an existing directory. Other common ones: `-f` (file exists), `-z` (empty string), `-eq`/`-gt`/`-lt` (numeric comparison). **Watch out**: the spaces inside `[ ]` are mandatory (`[-d "/path"]` without spaces gives an error).

### 2.6 — Functions

```bash
#!/usr/bin/env bash
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Starting backup"
tar -czf /var/backups/backup.tar.gz /etc/nginx
log "Backup complete"
```
→ Functions avoid repeating code. `$(date ...)` is "command substitution": it runs `date` and substitutes its output right there. This `log()` pattern with a timestamp is the bare minimum every production script should have.

### 2.7 — Mandatory production header

Now that you understand the individual pieces, here's the header that **every ops script must have**, and why:

```bash
#!/usr/bin/env bash
set -euo pipefail
```
→ Mandatory header in EVERY ops script:
- `set -e`: aborts if a command fails (prevents the script from continuing "blindly")
- `set -u`: errors if you use an undefined variable
- `set -o pipefail`: detects failures inside pipes (`cmd1 | cmd2`)

```bash
LOGFILE="/var/log/myapp/deploy.log"
exec > >(tee -a "$LOGFILE") 2>&1
```
→ Redirects stdout+stderr to a log and the screen simultaneously. **Why**: without this, if the process breaks at 3am you have no evidence.

```bash
if ! systemctl is-active --quiet nginx; then
  echo "ERROR: nginx is down" >&2
  systemctl restart nginx
fi
```
→ Check-then-fix pattern. `is-active --quiet` prints nothing, it just returns an exit code (0=active).

```bash
find /var/log -name "*.log" -mtime +30 -exec gzip {} \;
```
→ Compresses logs older than 30 days. **Symptom it fixes**: disk full from un-rotated logs.

```bash
df -h | awk '$5+0 > 80 {print $0}'
```
→ Filters partitions using more than 80%. `$5+0` forces numeric conversion of the `%`.

```bash
journalctl -u nginx.service --since "1 hour ago" -p err
```
→ systemd logs filtered by service, time, and priority (error). Replaces the outdated `tail -f /var/log/*`.

### 2.8 — Incident log

The real errors found practicing this phase (permissions in `/opt`, `if`/`fi` syntax, `tar` failing silently, `sh` vs `bash`, spaces in `process substitution`, permissions in `/var/log`) are documented separately in **[incidents-sre-eng.md](./incidents-sre-eng.md)**, section "PHASE 2 — Bash". It's worth keeping them in a separate file: this way you can keep adding incidents as you keep practicing, without the main playbook growing indefinitely — and in your GitHub repo, it's exactly the kind of troubleshooting evidence a portfolio reviewer values seeing as its own file.

---

## PHASE 3 — Python for Automation

**Official references:**

- [docs.python.org/3](https://docs.python.org/3/) — official Python documentation
- [PEP 668 — Marking Python base environments as "externally managed"](https://peps.python.org/pep-0668/) — spec behind the `externally-managed-environment` error
- [github.com/python/cpython](https://github.com/python/cpython) · [github.com/pypa/pip](https://github.com/pypa/pip)
- [crontab(5) — Linux man-pages](https://man7.org/linux/man-pages/man5/crontab.5.html) — official reference for the cron format

```bash
sudo apt install -y python3-pip python3-venv
python3 -m venv /opt/venvs/ops
source /opt/venvs/ops/bin/activate
```
→ **Never** `pip install` at the system level on modern Ubuntu (breaks apt). Always use isolated virtual environments.

**Fix if you get `source: command not found`**

This is the same pattern as Incident #4 in the log (bash vs `sh`/`dash`): `source` is a **bash built-in command**, it doesn't exist in `sh` (which on Ubuntu is `dash`, a more limited shell). If you see this error, your current session is running in `sh`, not `bash`.

**Diagnosis:**
```bash
echo $0
```
→ If it shows `sh` or `dash` (instead of `bash` or `-bash`), confirmed.

**Fix — two options:**

**Option 1**: use `.` (a single dot) instead of `source` — it's the POSIX equivalent, works in any shell, including `sh`:
```bash
. /opt/venvs/ops/bin/activate
```

**Option 2**: switch to bash before continuing:
```bash
bash
source /opt/venvs/ops/bin/activate
```
→ This opens a bash session inside your current session, where `source` does exist.

**Verify the venv is active** (either option):
```bash
which python
```
→ It should show `/opt/venvs/ops/bin/python`, not the system path.

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
        logging.error(f"Failed on {url}: {e}")
        return False

if __name__ == "__main__":
    ok = check_endpoint("http://localhost:8080/health")
    sys.exit(0 if ok else 1)
```
→ Basic healthcheck script. **Why Python and not bash here**: structured error handling, JSON parsing, reusable as a library.

```bash
pip install requests
pip freeze > requirements.txt
```
→ `freeze` pins exact versions. **Symptom it avoids**: "works on my machine" due to dependency drift.

### 3.0.1 — Crontab step by step: adding, verifying, and watching execution live

**1. Open your user's crontab**

```bash
crontab -e
```
→ Opens the scheduled tasks file for your current user (not root, unless you use `sudo crontab -e`). The **first time** you run it, it will ask which editor to use:
```
no crontab for opsuser - using an empty one

Select an editor.
  1. /bin/nano
  2. /usr/bin/vim
```
→ Choose `1` (nano) if you're not familiar with vim — it's simpler to edit and save.

**2. Understand the empty structure**

You'll see an almost empty file with only explanatory comments (lines starting with `#`, which cron ignores). At the end, add your line:

```
*/5 * * * * /opt/venvs/ops/bin/python /opt/scripts/healthcheck.py >> /var/log/healthcheck-cron.log 2>&1
```

Breakdown of the first 5 fields (the cron format):
```
*/5 *  *  *  *
│   │  │  │  │
│   │  │  │  └── day of the week (0-7, Sunday=0 or 7)
│   │  │  └───── month (1-12)
│   │  └──────── day of the month (1-31)
│   └─────────── hour (0-23)
└─────────────── minute (0-59)
```
→ `*/5 * * * *` = "every 5 minutes, every day, every hour". `*` just means "any value"; `*/5` means "every 5 units".

**3. Save and exit**

In nano: `Ctrl+O` → `Enter` (confirms the temp file name) → `Ctrl+X` (exit).

You'll see a confirmation message:
```
crontab: installing new crontab
```
→ This confirms cron accepted the syntax and installed it. If there had been a serious format error, cron would have flagged it here.

**4. Verify it was saved**

```bash
crontab -l
```
→ `-l` (list) prints the current crontab without opening the editor. It should show you exactly the line you added. **This is your first checkpoint** — if it doesn't appear, it wasn't saved.

**5. Prepare the log file BEFORE waiting**

```bash
sudo touch /var/log/healthcheck-cron.log
sudo chown $USER:$USER /var/log/healthcheck-cron.log
```
→ Same as in previous incidents: if the file doesn't exist or isn't yours, cron will silently fail when trying to write the log.

**6. Watch it run live**

This is where you actually "see" that cron is working. Open a terminal and leave this running:

```bash
tail -f /var/log/healthcheck-cron.log
```
→ `-f` (follow) keeps the file open and shows new lines as they're written — you don't have to keep re-running the command. Leave it running and wait for the next multiple of 5 minutes (e.g. if it's 10:32, wait until 10:35).

When cron fires the task, you'll see something like this appear live:
```
2026-08-26 10:35:01 INFO Healthcheck OK
```
or, if the endpoint doesn't respond:
```
2026-08-26 10:35:01 ERROR Failed on http://localhost:8080/health: Connection refused
```
→ That output is exactly the `logging.info`/`logging.error` you defined inside `healthcheck.py` — cron is simply invoking your script and redirecting its output there thanks to the `>> ... 2>&1` you added.

**7. Confirm in parallel that cron actually fired the task (not just your script)**

In another terminal, while you wait:
```bash
grep CRON /var/log/syslog | tail -5
```
→ You'll see a line like:
```
CRON[12345]: (opsuser) CMD (/opt/venvs/ops/bin/python /opt/scripts/healthcheck.py >> /var/log/healthcheck-cron.log 2>&1)
```
→ This confirms, at the system level, that cron read your crontab and executed the exact command — independent of whether your script succeeded or not. It's your proof that "cron did run" separate from "the script worked".

**8. Check the exit code of the last run (optional, for debugging)**

If you want to programmatically confirm whether the healthcheck passed or failed, remember that `sys.exit(0 if ok else 1)` in the script leaves that code available — but cron doesn't show it to you directly. To see it you'd need to capture it inside the command itself:
```
*/5 * * * * /opt/venvs/ops/bin/python /opt/scripts/healthcheck.py >> /var/log/healthcheck-cron.log 2>&1; echo "Exit code: $?" >> /var/log/healthcheck-cron.log
```
→ Adds the exit code to the same log, to know unambiguously whether each run succeeded (`0`) or failed (`1`).

---

### 3.0.2 — Quick reference of the original command

```bash
crontab -e
```
```
*/5 * * * * /opt/venvs/ops/bin/python /opt/scripts/healthcheck.py
```
→ Runs the check every 5 min. **Common fix**: cron uses a minimal PATH — always use absolute paths.

### 3.1 — Incident log

The errors from this phase (syntax typos in `def`/`if __name__`, `pip` outside the venv, venv permissions, broken cronjob in the `.cron` file) are documented in **[incidents-sre-eng.md](./incidents-sre-eng.md)**, section "PHASE 3 — Python".

---

## PHASE 4 — Docker

**Official references:**

- [docs.docker.com](https://docs.docker.com/) — official Docker Engine and Docker Compose documentation
- [github.com/moby/moby](https://github.com/moby/moby) — Docker Engine repository
- [github.com/docker/compose](https://github.com/docker/compose) — Docker Compose repository
- [hub.docker.com](https://hub.docker.com/) — official public image registry (nginx, mysql, mariadb, wordpress, etc.)

> **Context note**: this is a **test lab** for practice — not a real production server. That's why the install was done with the official one-command script (faster to spin the environment up and down repeatedly while learning), instead of the manual step-by-step process you'd typically use to document or audit each step in a production environment.

### 4.0 — Install: official `get-docker.sh` script

Docker offers a one-command install script that adds the GPG key, registers the official repository, and installs Docker Engine + Compose automatically. This was the method used for this practice server.

**1. Download the script (without running it yet)**

```bash
curl -fsSL https://get.docker.com -o get-docker.sh
```
→ Unlike `curl ... | sh` (which blindly executes the script while it downloads), using `-o get-docker.sh` saves it as a local file first. **Good security practice**: never run a script downloaded from the internet with `sudo` without being able to review it first.

**2. (Recommended) Inspect the script before running it**

```bash
less get-docker.sh
```
→ Lets you read what the script does (adding repos, installing packages, etc.) before giving it root privileges. Exit `less` with `q`.

**3. Run it first in test mode (`--dry-run`)**

```bash
sudo sh ./get-docker.sh --dry-run
```
→ `--dry-run` makes the script **show** which commands it would run (add repo, install packages, etc.) **without actually applying them**. It's the equivalent of `docker compose config` or `ansible-playbook --check` you already saw in other phases: it validates the plan before you commit to running it.

**4. Run the real install (dropping `--dry-run`)**

```bash
sudo sh ./get-docker.sh
```
→ Now it actually installs Docker Engine, CLI, `containerd`, and the buildx and compose plugins, all in one automated step.

**Verify the repo got registered (useful if something fails later):**
```bash
ls /etc/apt/sources.list.d/docker.*
```
→ Should show `docker.list` or `docker.sources` (the script picks the format based on your Ubuntu version). If at some point you see both pointing to the same repo, remove one of the two to avoid duplicates.

**5. Add your user to the `docker` group**

```bash
sudo usermod -aG docker krikox
```
→ Specifically adds the user `krikox` (the real working user on this server, confirmed with `whoami` in earlier incidents) to the `docker` group.

```bash
exit
```
And reconnect — remember that `newgrp` isn't always enough after a `usermod` (Incident #12 in the log).

**6. Verify it's working**

```bash
groups
docker run hello-world
docker compose version
```

**7. Additional test with a real image: nginx**

To confirm the full container cycle works beyond `hello-world` (which just prints text and exits), a real web server image was downloaded and run:

```bash
docker pull nginx
```
→ Downloads the official nginx image from Docker Hub, without running it yet.

```bash
docker run -d --name nginx-test -p 8081:80 nginx
```
→ Runs it in the background (`-d`), mapping port 8081 on your server to port 80 inside the container (where nginx listens by default).

**Verify it responds:**
```bash
curl http://localhost:8081
```
→ Should return the nginx welcome HTML (`<h1>Welcome to nginx!</h1>` in the body). This confirms container networking works end to end — not just that Docker runs a process, but that it correctly exposes ports to the host.

```bash
docker ps
```
→ Should show `nginx-test` with `Up` status and the port mapping `0.0.0.0:8081->80/tcp`.

---

### 4.1 — Quick reference (once already installed)

```bash
docker run hello-world
```
→ Downloads (if you don't have it locally) and runs the official `hello-world` test image. You'll see text output explaining what just happened internally. **What it exactly confirms**:
1. The Docker client (`docker`) was able to talk to the Docker daemon (`dockerd`) — confirms the service is running.
2. The daemon was able to download the image from Docker Hub — confirms you have internet access and working DNS.
3. The daemon created a container from that image, ran it, and the container printed its message and exited — confirms the full container cycle working end to end.

**Verify the image was downloaded locally:**
```bash
docker images
```
→ You should see `hello-world` in the list. You can delete the already-used test container with `docker ps -a` (to see stopped containers) and `docker rm <container_id>` — no need to keep it.

---

### 4.2 — Easy image: MySQL

**1. Download the official MySQL image from Docker Hub**

```bash
docker pull mysql
```
→ The official Docker image for MySQL was used from Docker Hub (`docker pull` downloads the image without running it yet). Official image page: **[hub.docker.com/_/mysql](https://hub.docker.com/_/mysql)** — all available environment variables and supported versions/tags are documented there.

**2. Install the MySQL client on the system (to be able to connect from outside the container)**

```bash
sudo apt install mysql-client
```
→ Installed with `apt install mysql` to be able to get into the Docker container from the server's terminal with the `mysql` command, instead of relying solely on `docker exec`.

**3. Launch the container with a name and password**

```bash
docker run --name database -e MYSQL_ROOT_PASSWORD=12345 -d mysql
```
→ Breakdown:
- `--name database`: gives the container a fixed name (instead of an autogenerated random one), to easily reference it in later commands (`docker logs database`, `docker stop database`, etc.).
- `-e MYSQL_ROOT_PASSWORD=12345`: mandatory environment variable — MySQL won't start without it, sets the `root` user password.
- `-d`: runs in the background (detached).

**Verify it's running:**
```bash
docker ps
```

**Connect — method 1: from inside the container with `docker exec`**
```bash
docker exec -it database mysql -uroot -p
```
→ It will ask for the password (`12345` in this case). Exit with `exit` or `\q`.

**Connect — method 2: from the host, using the `mysql` client installed in step 2**

First you need the container's internal IP (the one Docker assigned it on its network):

```bash
docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' database
```
→ Returns something like `172.17.0.2` — it's the IP within Docker's default bridge network (`docker0`), not the server's public IP.

With that IP, connect using the `mysql` client you installed on the host (not `docker exec`):

```bash
mysql -u root -h 172.17.0.2 -p12345
```
→ Breakdown:
- `-u root`: user.
- `-h 172.17.0.2`: host — the container's IP obtained above (adjust if yours is different).
- `-p12345`: password **attached directly to the flag**, with no space (`-p12345`, not `-p 12345`). If you add a space, `mysql` interprets what follows as a separate argument and prompts for the password interactively instead.

**Security note**: passing the password directly in the command (`-p12345`) leaves it visible in your terminal history (`history`) and in the process list (`ps aux`) while it runs. For real use (not just practice), it's safer to use `-p` alone (without the value attached) and type it when prompted, or use environment variables/config files (`~/.my.cnf`).

**Difference between the two methods**: method 1 (`docker exec`) always works regardless of the container's IP, because Docker resolves the name internally. Method 2 (direct IP) is useful to confirm the container correctly exposes the connection at the network level — but if the container restarts, the IP can change, so don't treat it as fixed in scripts or permanent configs.


### 4.3 — Docker Compose: official install and step-by-step examples

#### 4.3.0 — Installation (official documentation)

Installed following the official documentation: **[docs.docker.com/compose/install/linux](https://docs.docker.com/compose/install/linux/)**.

```bash
sudo apt-get update
sudo apt-get install docker-compose-plugin
```
→ Installs the Compose plugin from the Docker repository already registered (if you followed section 4.0 with `get-docker.sh`, this package is probably already installed — this command doesn't hurt anyway, `apt` just confirms it's already at the latest version).

**Verify the install:**
```bash
docker compose version
```
→ Should show a version number (e.g. `Docker Compose version v2.x.x`), with no errors. If it says `is not a docker command`, check section 4.0 — it means the Docker repository never got registered in `apt` (same diagnosis as Incident #13 in the log).

---

#### 4.3.1 — Example 1: a simple service (nginx)

The typical Compose workflow is: edit the file with `nano`, bring down the previous stack (if there was one), and bring up the new one. That's how each example in this section was tested.

**Create the file:**
```bash
mkdir -p /opt/apps/compose-lab
cd /opt/apps/compose-lab
nano compose.yaml
```

**Content:**
```yaml
services:
  web:
    image: nginx:latest
    ports:
      - "8080:80"
```
→ A single service (`web`), using the official nginx image, exposing the container's port 80 as 8080 on the host.

**Bring up the stack:**
```bash
docker compose up -d
```

**Verify:**
```bash
curl http://localhost:8080
```
→ Should return the nginx welcome HTML.

---

#### 4.3.2 — Example 2: building a Dockerfile with Compose

In this case, a Dockerfile in the same folder as the compose file gets built. To do that, add the `build` key to the service instead of `image`.

**Bring down the previous stack before switching examples:**
```bash
docker compose down
```

**Edit the file:**
```bash
nano compose.yaml
```

**New content:**
```yaml
services:
  web:
    build: .
    ports:
      - "8080:80"
```
→ `build: .` tells Compose that, instead of downloading a pre-built image, it should build a new one using the `Dockerfile` that must exist in the same directory (`.` = current directory, the same build context you already saw with `docker build`). Compose handles the `docker build` internally before bringing up the container.

**Bring it up (this time it does build the image first):**
```bash
docker compose up -d
```
→ You need a valid `Dockerfile` in `/opt/apps/compose-lab` for this example to work — without one, Compose fails with `Dockerfile not found`.

---

#### 4.3.3 — Example 3: multiple services and routing between containers

The previous example is completed with another container, to make requests to the nginx service and demonstrate how Compose resolves routing between services automatically.

**Bring down the previous stack:**
```bash
docker compose down
```

**Edit the file:**
```bash
nano compose.yaml
```

**New content:**
```yaml
services:
  web:
    image: nginx
  test:
    image: nginx
```
→ Two services: `web` (the nginx server) and `test` (the container from which requests are made).

> **Note**: for the `curl` command in the next step to work inside the `test` container, that image needs to have `curl` installed — the base nginx image doesn't include it by default. If `curl` isn't available, use an image that does have it (e.g. `curlimages/curl`) or install it via your own Dockerfile for that service.

**Bring up the stack:**
```bash
docker compose up -d
```

**Open an interactive terminal inside the `test` container:**
```bash
docker compose exec test sh
```
→ `exec` opens an interactive session inside an **already running** container in the stack (equivalent to `docker exec -it`, but using the service name instead of the container name/ID). Here, `test` is the name of the service we want to enter.

**From inside the `test` container, make a request to the `web` service by name:**
```bash
curl web:80
```
→ Here's the key part: `web` is the service name defined in `compose.yaml`, **not an IP**. Compose automatically creates an internal network where each service can resolve the others by name — you never have to specify IPs manually when working with Compose (this also applies to Kubernetes and other orchestrators, where the same service-name-discovery pattern is standard).

---

#### 4.3.4 — Verify the status of the services

Important after any install or change, to confirm the whole stack is actually running:

```bash
docker compose ps
```
→ Shows the status of the services defined in the compose (unlike `docker ps`, which shows ALL containers on the system, this one filters just to this project/folder).

```bash
docker compose logs -f
```
→ Aggregated logs from all services in the stack in real time — useful for debugging when a service doesn't start properly.

---

#### 4.3.5 — More complete example: WordPress + MariaDB

As a more complete example, WordPress was deployed with a MariaDB database, with the services defined in separate blocks within the same `compose.yaml`.

**Bring down the previous stack:**
```bash
docker compose down
```

**Full file:**
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

**Block-by-block breakdown:**

**`db` block (MariaDB):**
- `image: mariadb:10.6.4-focal`: official MariaDB image, with support for `amd64` and `arm64` architectures — important if your server isn't traditional Intel/AMD (for example, a Raspberry Pi or an ARM instance in the cloud).
- `command: '--default-authentication-plugin=mysql_native_password'`: overrides the container's startup command, forcing the classic MySQL authentication plugin — needed for compatibility with WordPress, which expects that method.
- `volumes: - db_data:/var/lib/mysql`: persists the database data in the named volume `db_data`, so it isn't lost if the container gets recreated.
- `restart: always`: the container restarts automatically on any crash, even after a server reboot (more aggressive than `unless-stopped`, which you already saw in Docker run — `always` ignores it even if you stopped it manually).
- `environment`: variables MariaDB uses on its first startup to create the root user, the initial database, and the application user (`wordpress`).
- `expose: - "3306" - "33060"`: unlike `ports`, `expose` **does not publish the port to the host** — it only makes it accessible to other containers on the same Compose network. It's the correct choice for a database that should only be reachable by `wordpress`, not from the internet.

**`wordpress` block:**
- `image: wordpress:latest`: official WordPress image.
- `volumes: - wp_data:/var/www/html`: persists WordPress files (themes, plugins, uploads) in the `wp_data` volume.
- `ports: - "8080:80"`: unlike `expose` in the `db` block, `ports` is used here because WordPress needs to be accessible from the browser — maps host port 8080 to container port 80.
- `environment`: `WORDPRESS_DB_HOST=db` is the key part — `db` is the MariaDB service name defined above, so WordPress connects to the database by service name, with no IPs (same pattern seen in Example 3).

**`volumes` block (root level, outside `services`):**
```yaml
volumes:
  db_data:
  wp_data:
```
→ Declares the two named volumes used above. Without this block, Compose would create them implicitly anyway, but declaring them explicitly is good practice — it makes clear in the file which data persists.

**Bring up the full stack:**
```bash
docker compose up -d
```

**Verify:**
```bash
docker compose ps
```
→ Both services (`db` and `wordpress`) should appear with `Up` status.

Open `http://<SERVER_IP>:8080` in your browser — it should load the initial WordPress installer.

---

#### 4.3.6 — General maintenance commands

**Edit and reapply changes:**
```bash
nano compose.yaml
docker compose up -d
```
→ Compose automatically detects what changed and only recreates the affected services, without needing to bring everything down first.

**Stop and clean up:**
```bash
docker compose down
```
→ Stops and removes the stack's containers (keeps the images). To also remove associated volumes (⚠️ deletes data, like the WordPress database):
```bash
docker compose down -v
```

---

#### 4.3.7 — References

Researched and referenced Docker's official documentation and this community guide:
- [docs.docker.com/compose/install/linux](https://docs.docker.com/compose/install/linux/) — official installation
- [github.com/pabpereza/pabpereza — Docker Compose](https://github.com/pabpereza/pabpereza/blob/main/docs/cursos/docker/112.Docker_compose.md) — reference guide for the build, multi-service, and routing examples

---

## PHASE 5 — Kubernetes

**Official references:**

- [docs.k3s.io](https://docs.k3s.io) — official k3s documentation (install, architecture, config, HA, upgrades)
- [github.com/k3s-io/k3s](https://github.com/k3s-io/k3s) — project repository, includes `install.sh` and release notes
- [kubernetes.io/docs](https://kubernetes.io/docs/home/) — official "upstream" Kubernetes documentation (concepts, `kubectl`, manifests) — k3s is a conformant Kubernetes distribution, so most concepts (Pods, Deployments, Services) apply the same way, only the install method/internal architecture changes

**Note**: for a single learning server, use **k3s** (lightweight Kubernetes) instead of full kubeadm.

```bash
curl -sfL https://get.k3s.io | sh -
sudo k3s kubectl get nodes
```
→ Installs a single-node cluster. **Why k3s**: kubeadm requires ≥2 CPU/2GB per node and more steps; k3s is production-viable for small/edge clusters.

```bash
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
export KUBECONFIG=~/.kube/config
```
→ Configures `kubectl` so you don't have to rely on `sudo k3s kubectl` every time.

**Create a folder for your Kubernetes manifests:**
```bash
mkdir -p /opt/k8s
cd /opt/k8s
nano deployment.yaml
```
→ Same convention as `/opt/apps` for Docker and `/opt/scripts` for bash/Python — keeps each type of artifact in its own directory. This is where you write the content below.

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 2
  selector:
    matchLabels: {app: myapp}
  template:
    metadata:
      labels: {app: myapp}
    spec:
      containers:
      - name: myapp
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
  name: myapp-svc
spec:
  selector: {app: myapp}
  ports: [{port: 80, targetPort: 80}]
  type: ClusterIP
```
→ `resources` prevents a pod from consuming the whole node (**symptom it prevents**: noisy neighbor). `livenessProbe` restarts the pod if it stops responding. `nginx:latest` (a real public image) is used instead of your own image like `myapp:1.0` — so this example works as-is without depending on you having built and published your own image first.

```bash
kubectl apply -f deployment.yaml
kubectl get pods -w
```
→ Applies the manifest; `-w` watches changes in real time (useful for watching rollouts).

**Fix if you get `ErrImagePull` / `ImagePullBackOff`**

```
myapp-668ff4fdbf-99z8d   0/1   ErrImagePull       0   9s
myapp-668ff4fdbf-99z8d   0/1   ImagePullBackOff   0   15s
```
→ It means k3s couldn't download the image specified in `image:`. This error used to show up with `image: myapp:1.0` because that image was **never built or published** to any registry — it was just a generic example name. `ImagePullBackOff` is the "retry with exponential backoff" state Kubernetes uses after several `ErrImagePull` in a row, not a new error.

**Diagnosis:**
```bash
kubectl describe pod <pod-name>
```
→ Look at the `Events` section at the end — it shows the exact message from the pull attempt (e.g. `manifest unknown`, `pull access denied`, `not found`).

**Typical causes and fixes:**
1. **Typo in the image name or tag** — check that `image:` in the YAML exactly matches an image that exists on Docker Hub (or the registry you're using).
2. **Image built locally with `docker build`, but k3s can't see it** — this is the most common and most confusing cause at first: **k3s uses its own `containerd` runtime, completely separate from the Docker daemon**. An image that exists in `docker images` (built with `docker build -t myapp:1.0 .`) **isn't automatically visible to k3s** — they live in two different image "stores", even though they're on the same server. To use a local image in k3s, you have to import it explicitly:
   ```bash
   docker save myapp:1.0 | sudo k3s ctr images import -
   ```
   → Exports the image from the Docker daemon and imports it into k3s's containerd. A more standard alternative in production: push the image to a registry (Docker Hub, GitHub Container Registry, etc.) with `docker push`, and reference that full path in the YAML (e.g. `image: username/myapp:1.0`) — that way any node in the cluster can download it without depending on it already existing locally.
3. **Private image without configured credentials** — if you use a private registry, k3s needs a configured `imagePullSecret`; without it, the pull fails with `pull access denied` even if the image exists.

```bash
kubectl describe pod <pod-name>
kubectl logs <pod-name> --previous
```
→ **Standard fix when a pod crashes**: `describe` shows events (OOMKilled, ImagePullBackOff, etc.), `--previous` shows logs from the container prior to the last crash.

```bash
kubectl rollout status deployment/myapp
kubectl rollout undo deployment/myapp
```
→ Checks rollout status; `undo` does an immediate rollback to the previous version. **Use case**: a bad production deploy.

### 5.1 — How to check if a pod is working

Different levels of verification, from quick to detailed.

**1. Quick view — general status**

```bash
kubectl get pods
```
→ Key column: `STATUS`, should say `Running`. The `READY` column (e.g. `1/1`) confirms the container **inside** the pod passed its `readinessProbe` (if it has one configured) — `0/1` with `Running` status means the pod started, but the container isn't ready to receive traffic yet.

```bash
kubectl get pods -o wide
```
→ Adds extra columns: which node it's running on, its internal IP, etc. — useful in clusters with more than one node.

**2. Watch it in real time as it changes**

```bash
kubectl get pods -w
```
→ `-w` (watch) leaves the terminal watching status changes live, useful right after an `apply` or `rollout`.

**3. Full detail — when something isn't right**

```bash
kubectl describe pod <pod-name>
```
→ Shows everything: recent events (at the end, `Events` section), which image it uses, resources, configured probes, and why it failed if it did. It's the first command to run when `STATUS` doesn't say `Running`.

**4. Container logs — confirm the app itself is working well, not just that the process started**

```bash
kubectl logs <pod-name>
```
```bash
kubectl logs -f <pod-name>
```
→ `-f` live, same as `docker logs -f`. This confirms whether the app is serving traffic correctly, beyond Kubernetes reporting `Running`.

**5. Real functional test — confirm it responds to traffic**

```bash
kubectl port-forward <pod-name> 8080:80
```
→ Maps port 80 of the pod to 8080 on your machine temporarily. **Important**: the format is `<local-port>:<pod-port>` — if you write only one number (`kubectl port-forward <pod> 8080`), Kubernetes uses that same number for both sides (local **and** the pod's), which fails if your container doesn't listen exactly on 8080 (the `nginx:latest` from this phase's manifest listens on port **80**, not 8080 — that's why the two-port format, `8080:80`, is correct).

Then, in another terminal:
```bash
curl http://localhost:8080
```
→ This is the most reliable test: it doesn't just confirm the pod "exists", it confirms it responds to real traffic — equivalent to the `curl` you already used to validate the `nginx-test` Docker container.

**Fix if you get `bind: address already in use`**

```
Unable to listen on port 8080: Listeners failed to create with the following errors:
[unable to create listener: Error listen tcp4 127.0.0.1:8080: bind: address already in use ...]
```
→ Local port **8080 is already occupied by another process** on your server — `kubectl port-forward` can't listen there again. It's a port conflict on the host, not a pod or Kubernetes problem.

**Diagnosis — check what's already using 8080:**
```bash
sudo ss -tlnp | grep 8080
```
→ Very likely the Docker `nginx-test` container (PHASE 4) or the WordPress stack (section 4.3.5), both mapped to `8080:80` on the host — if you left either one running, it's still occupying that port at the OS level, unrelated to Kubernetes.

```bash
docker ps
```
→ Confirms whether any of those containers are still active.

**Fix — two options:**

**Option 1**: use a different local port for the `port-forward` (doesn't need to match the pod's port):
```bash
kubectl port-forward <pod-name> 8081:80
curl http://localhost:8081
```

**Option 2**: free up port 8080 by stopping the Docker container using it:
```bash
docker stop nginx-test
kubectl port-forward <pod-name> 8080:80
```

**Summary — what to check depending on what you need to confirm:**

| You want to know | Command |
|---|---|
| Is it running? | `kubectl get pods` |
| Why didn't it start? | `kubectl describe pod <name>` |
| What is the app printing? | `kubectl logs <name>` |
| Does it actually respond to traffic? | `kubectl port-forward` + `curl` |

---

## PHASE 6 — Ansible: Infrastructure Automation

**Official references:**

- [docs.ansible.com](https://docs.ansible.com/) — official Ansible documentation
- [github.com/ansible/ansible](https://github.com/ansible/ansible) — main repository (ansible-core)
- [ansible.builtin.file](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/file_module.html) · [ansible.builtin.template](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/template_module.html) · [community.docker.docker_container](https://docs.ansible.com/projects/ansible/latest/collections/community/docker/docker_container_module.html) — modules used in this phase
- [github.com/ansible-collections/community.docker](https://github.com/ansible-collections/community.docker) — repository for Ansible's Docker collection

```bash
sudo apt install -y ansible
```
→ On the **control** node (not on the managed servers).

**Create a folder for your Ansible files:**
```bash
mkdir -p /opt/ansible
cd /opt/ansible
nano inventory.ini
```
→ Same convention as the rest of the playbook: `/opt/apps` for Docker, `/opt/scripts` for bash/Python, `/opt/k8s` for Kubernetes manifests, and now `/opt/ansible` for the inventory and playbooks. This is where you write the content below.

```ini
# inventory.ini
[web]
srv-prod-01 ansible_connection=local

[web:vars]
ansible_python_interpreter=/usr/bin/python3
```
→ `ansible_connection=local` tells Ansible to run the modules **directly on this machine**, without going through SSH. In this homelab, the control node and the managed node are the same server, so there's no point setting up SSH just to connect to yourself — Ansible runs the tasks locally, with the same result.

> **Note — environments with multiple real servers**: in a cluster with more than one server, you would need real SSH between the control node and each managed node. In that case, the inventory would use `ansible_host=<server-IP>`, `ansible_user=<user>`, and `ansible_port=<ssh-port>` instead of `ansible_connection=local` — and that managed server would need `openssh-server` installed and running (`sudo apt install -y openssh-server && sudo systemctl enable ssh --now`), with your public SSH key added to its `~/.ssh/authorized_keys`.

```bash
ansible web -i inventory.ini -m ping
```
→ Connectivity test. With `ansible_connection=local`, it should respond `SUCCESS` with `"ping": "pong"` immediately — there's no SSH handshake that can fail.

**Fix if you get `sudo: a password is required` or similar when using `become: true` later**

With a local connection, `become` (used in the playbook below) calls `sudo` directly in your current session. If your user needs a password for `sudo` (doesn't have NOPASSWD configured), Ansible will ask for it interactively:
```bash
ansible-playbook -i inventory.ini playbook.yml --ask-become-pass
```
→ `--ask-become-pass` makes Ansible ask for the `sudo` password before executing, instead of failing silently.

**Create the playbook in the same folder:**
```bash
nano playbook.yml
```

```yaml
# playbook.yml
- hosts: web
  become: true
  tasks:
    - name: Update packages
      apt: {update_cache: yes, upgrade: dist}

    - name: Install Docker
      apt: {name: docker.io, state: present}

    - name: Ensure Docker is active
      systemd: {name: docker, state: started, enabled: true}

    - name: Create app directory
      file:
        path: /opt/app
        state: directory
        mode: "0755"

    - name: Copy app config
      template:
        src: app.env.j2
        dest: /opt/app/.env
        mode: "0600"
      notify: restart app

  handlers:
    - name: restart app
      docker_container:
        name: myapp
        image: nginx:latest
        state: started
        restart: true
```
→ `become: true` = elevates to sudo when running (in this case, on the same local machine, thanks to `ansible_connection=local`; in a multi-server environment it would be sudo on each remote host). `handlers` only fire if the task that `notify`-ed them actually changed something (idempotency). **Key concept**: Ansible is declarative — you describe the final state, not the steps. The `Create app directory` task (`file` module, `state: directory`) is needed because the `template` module **doesn't create intermediate directories automatically** — if `/opt/app` doesn't exist before trying to copy `.env` there, it fails with `Destination directory /opt/app does not exist`. The handler uses `docker_container` with `image: nginx:latest` (the same public image already used in Docker and Kubernetes) — without the `image:` key, the module doesn't know which image to use if the `myapp` container doesn't exist yet, and fails with `Cannot create container when image is not specified!`.

**Important note about `--check` with this task**: since the handler creates/restarts a Docker container (an action with real effect), in `--check` (dry-run) mode Ansible can simulate it without actually running it. To confirm the container really stays up, also run it without `--check`:
```bash
ansible-playbook -i inventory.ini playbook.yml --ask-become-pass
docker ps
```
→ `myapp` should appear running with the `nginx:latest` image.

```bash
ansible-playbook -i inventory.ini playbook.yml --check
```
→ **Dry-run**: shows what would change WITHOUT applying it. Always use this before running in production.

```bash
ansible-playbook -i inventory.ini playbook.yml
```
→ Real execution.

```bash
ansible-vault encrypt secrets.yml
ansible-playbook -i inventory.ini playbook.yml --ask-vault-pass
```
→ Encrypts credentials/secrets in the repo. **Never** plaintext secrets in Git.

### 6.1 — Final validation: confirm the container created by Ansible is still running

The `restart app` handler in the playbook created the `myapp` container with the `docker_container` module — **not** with Docker Compose, so you need to verify it with the correct command.

**1. `docker compose ps` won't show it — use `docker ps`**

```bash
docker ps
```
→ `docker compose ps` only lists containers belonging to a Compose project (created with `docker compose up` from a `compose.yaml`). Ansible's `docker_container` module talks directly to the Docker API, without going through Compose — the container doesn't have the project label `compose ps` looks for, so it stays invisible there even though it's running fine.

```bash
docker ps -a
```
→ If `myapp` doesn't show up running, check here — it might be in `Exited` state.

**2. If the status is `Exited`, diagnose before blindly restarting**

```bash
docker inspect myapp --format='Exit Code: {{.State.ExitCode}} | Error: {{.State.Error}} | OOMKilled: {{.State.OOMKilled}}'
```
→ The `Exit Code` is the main clue:
- `0` = the process ended normally (something told it to stop, not a crash)
- `137` = it was killed by the system (often memory — check if `OOMKilled` says `true`)
- Any other number = the process failed with that error code

```bash
docker logs myapp
```
→ Almost always tells you exactly what happened inside the container.

**3. Typical cause: `restart: true` in the module isn't a persistent restart policy**

```bash
docker inspect myapp --format='RestartPolicy: {{.HostConfig.RestartPolicy.Name}}'
```
→ The `restart: true` used in the Ansible handler only tells Docker "restart the container now, once", during the playbook run — unlike `--restart unless-stopped` (used in Docker run from PHASE 4), it doesn't configure the container to restart itself on future failures. If `myapp` failed after that one-time restart, it stays `Exited` with nobody watching it.

**Fix — add a real restart policy in the playbook:**
```yaml
handlers:
  - name: restart app
    docker_container:
      name: myapp
      image: nginx:latest
      state: started
      restart: true
      restart_policy: unless-stopped
```
→ `restart_policy: unless-stopped` is actually persistent — the container restarts automatically on crashes or server reboots, same as `--restart unless-stopped` in `docker run`.

**4. Restart manually and confirm it stays up:**
```bash
docker start myapp
docker logs -f myapp
```
→ Watch it for a few seconds — if it exits again on its own (`Exited` again), the problem is in the app/image, not the restart policy.

---

## PHASE 7 — Automated Monitoring (Prometheus + Grafana + Node Exporter)

**Official references:**

- [prometheus.io/docs](https://prometheus.io/docs/introduction/overview/) — official Prometheus documentation
- [grafana.com/docs](https://grafana.com/docs/) — official Grafana documentation
- [github.com/prometheus/prometheus](https://github.com/prometheus/prometheus) · [github.com/prometheus/node_exporter](https://github.com/prometheus/node_exporter) · [github.com/grafana/grafana](https://github.com/grafana/grafana)
- [grafana.com/grafana/dashboards](https://grafana.com/grafana/dashboards/) — community dashboard repository (includes dashboard 1860 used in this phase)

```bash
sudo useradd --no-create-home --shell /usr/sbin/nologin node_exporter
```
→ System user with no login or home, for security (services shouldn't run as interactive users).

### 7.1 — Install node_exporter, step by step

**1. Resolve the latest version and download**

```bash
cd ~
NODE_EXPORTER_VERSION=$(curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest | grep '"tag_name"' | cut -d '"' -f4 | sed 's/^v//')
echo "Detected version: $NODE_EXPORTER_VERSION"
curl -LO "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
```
→ The version is resolved dynamically by querying the GitHub API (`tag_name` of the latest release) instead of hardcoding a version number in the URL — a hardcoded number combined with `/latest/download/` will eventually go stale: if the real "latest" version no longer matches the one written by hand, GitHub responds with an HTML 404 error page instead of the file, and `curl -O` saves it anyway with a `.tar.gz` extension.

**2. Verify you downloaded a real file, not an error page, BEFORE extracting**

```bash
file node_exporter-*.tar.gz
```
→ Should say `gzip compressed data`. If it says `HTML document` or `ASCII text`, you downloaded a 404 error page — delete it and repeat step 1:
```bash
rm -f node_exporter-*.tar.gz
```

**3. Extract the file**

```bash
tar xvf node_exporter-*.tar.gz
```

**4. Confirm the binary exists inside the extracted folder BEFORE moving it**

```bash
ls -la ~ | grep node_exporter
```
→ Should show a `node_exporter-<version>.linux-amd64/` folder (no extension) alongside the original `.tar.gz`. Verify the binary is inside it:
```bash
ls -l ~/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/
```
→ Should list `node_exporter` (the executable binary), along with `LICENSE` and `NOTICE`.

**5. Move the binary to `/usr/local/bin`**

```bash
sudo mv ~/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/
```
→ Uses the full path with the `$NODE_EXPORTER_VERSION` variable (instead of the wildcard `node_exporter-*/node_exporter`) to unambiguously point to the exact folder, especially if leftovers from earlier attempts with other versions remain in the same directory.

**6. Verify the binary got installed and responds**

```bash
node_exporter --version
```
→ Should print the version with no `command not found` error. If it fails, confirm `/usr/local/bin` is in your `PATH` (`echo $PATH`) or try the absolute path: `/usr/local/bin/node_exporter --version`.

**7. Cleanup — you no longer need the folder or the `.tar.gz`**

```bash
rm -rf ~/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64 ~/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
```

**Create the service definition file:**
```bash
sudo nano /etc/systemd/system/node_exporter.service
```
→ Unlike `/opt/scripts`, `/opt/k8s`, or `/opt/ansible` (your own folders), systemd `.service` files **must** live in `/etc/systemd/system/` — it's the standard path where systemd looks for user/third-party service definitions (different from `/lib/systemd/system/`, reserved for services that come packaged with `apt`). That's why the command goes straight to `sudo nano`, no prior `mkdir` — the directory already exists on any Ubuntu.

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
→ Paste this content inside `nano` and save as usual: `Ctrl+O` → `Enter` → `Ctrl+X`.

```bash
sudo systemctl daemon-reload
sudo systemctl enable node_exporter --now
```
→ Turns it into a persistent systemd service (survives reboots).

**Create a folder for the monitoring stack:**
```bash
mkdir -p /opt/monitoring
cd /opt/monitoring
nano docker-compose.monitoring.yml
```
→ Same convention as the rest of the playbook: `/opt/apps` for Docker, `/opt/scripts` for bash/Python, `/opt/k8s` for Kubernetes, `/opt/ansible` for Ansible, and now `/opt/monitoring` for Prometheus/Grafana. This is where you write the content below.

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
→ Monitoring stack via Docker (simpler than installing everything natively). Save as usual: `Ctrl+O` → `Enter` → `Ctrl+X`.

**Create the second file, in the same folder:**
```bash
nano prometheus.yml
```
→ **Important**: it must be named exactly `prometheus.yml` and be in the **same folder** as `docker-compose.monitoring.yml` — the `volumes:` above references it with a relative path (`./prometheus.yml`), so if you create it in another directory, Compose won't find it when bringing up the stack.

```yaml
# prometheus.yml
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: "node"
    static_configs:
      - targets: ["<SERVER_IP>:9100"]
  - job_name: "kubernetes"
    static_configs:
      - targets: ["<SERVER_IP>:10250"]
```
→ Defines how often and from where Prometheus collects metrics (`scrape`).

**Verify both files ended up in the same folder before bringing up the stack:**
```bash
ls -la /opt/monitoring/
```
→ Should show `docker-compose.monitoring.yml` and `prometheus.yml` together.

```bash
docker compose -f docker-compose.monitoring.yml up -d
```
→ Brings up Prometheus and Grafana in the background. This command only creates the containers — the next steps are to confirm they're accessible and connect them to each other.

### 7.2 — Bring up the stack and access it via browser, step by step

**1. Verify both containers are running**

```bash
docker compose -f docker-compose.monitoring.yml ps
```
→ Should show `prometheus` and `grafana` with `Up` status. If either doesn't appear or is `Exited`, check its logs before continuing:
```bash
docker compose -f docker-compose.monitoring.yml logs prometheus
docker compose -f docker-compose.monitoring.yml logs grafana
```

**2. Confirm the ports are correctly exposed**

```bash
sudo ss -tlnp | grep -E '9090|3000'
```
→ Should show both ports listening (`9090` for Prometheus, `3000` for Grafana).

**3. Access Prometheus from the browser**

Open in your browser:
```
http://<SERVER_IP>:9090
```
→ Replace `<SERVER_IP>` with your server's real IP (`hostname -I` if you don't have it handy). Should load the Prometheus web interface.

**Example with a real IP** (assuming `hostname -I` returned `192.168.100.42` — typical in VirtualBox Bridged Adapter mode, already visible directly from your local network):
```
http://192.168.100.42:9090
```

**Confirm Prometheus is collecting metrics from your targets:**
```
http://<SERVER_IP>:9090/targets
```
→ Example: `http://192.168.100.42:9090/targets`. This page lists each `job` defined in `prometheus.yml` (`node`, `kubernetes`) with its status: **`UP`** in green means Prometheus is successfully scraping that metric; **`DOWN`** in red means it can't reach that target — check the IP/port in `prometheus.yml` and that `node_exporter` is running there (section 7.1).

**Try a simple query**, directly in the Prometheus UI search bar ("Graph" tab):
```
node_cpu_seconds_total
```
→ If you see results with data, it confirms `node_exporter` metrics are arriving end to end.

**4. Access Grafana from the browser**

Open in your browser:
```
http://<SERVER_IP>:3000
```
→ Example: `http://192.168.100.42:3000`. Grafana login screen. Default credentials on first access:
- User: `admin`
- Password: `admin`

→ Grafana will ask you to change the password immediately after the first login — do it, don't leave the default password on a network-accessible server, even if it's a lab.

**5. Connect Grafana to Prometheus as a data source**

Inside the Grafana UI:
```
Side menu (gear icon) → Connections → Data Sources → Add data source → Prometheus
```
→ In **URL**, type:
```
http://prometheus:9090
```
→ **Important**: here you use `prometheus` (the service name in `docker-compose.monitoring.yml`), **not** `localhost` or the server's IP — Grafana runs inside the same Docker Compose network as Prometheus, so they reach each other by service name, just like you saw with `curl web:80` in Docker Compose Example 3 (section 4.3.3).

Click **Save & Test** at the end of the form — it should confirm `Successfully queried the Prometheus API`.

**6. Import the industry-standard dashboard**

```
Side menu → Dashboards → New → Import
```
→ In the "Import via grafana.com" field, type the dashboard ID:
```
1860
```
→ This is the **Node Exporter Full** dashboard, the most widely used community one for visualizing `node_exporter` metrics — no need to build your own from scratch. Click **Load**, select the Prometheus data source you added in step 5, and click **Import**.

**7. Confirm the dashboard shows real data**

→ Should load CPU, memory, disk, and network graphs for the server, with values updating every `scrape_interval` (15s, per `prometheus.yml`). If the graphs appear empty ("No data"), go back to step 3 and confirm the `node` target is `UP` in `/targets` — an empty dashboard almost always means the data source has no metrics to show, not a problem with the dashboard itself.

### 7.3 — Basic alerts, step by step

**1. Create the file in the same folder as the monitoring stack**

```bash
cd /opt/monitoring
nano alert.rules.yml
```
→ Same directory as `docker-compose.monitoring.yml` and `prometheus.yml` (section 7.2, step 1) — Prometheus needs to be able to mount this file from there.

**Content:**
```yaml
# alert.rules.yml
groups:
  - name: node-alerts
    rules:
      - alert: DiskFull
        expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 < 15
        for: 5m
        labels: {severity: critical}
        annotations: {summary: "Less than 15% disk free on {{ $labels.instance }}"}

      - alert: HighCPU
        expr: 100 - (avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 85
        for: 10m
        labels: {severity: warning}
```
→ `for: 5m` avoids false positives from momentary spikes (**key pattern**: alert on a sustained state, not an instantaneous one). Save as usual: `Ctrl+O` → `Enter` → `Ctrl+X`.

**2. Connect the rules file to Prometheus — two required changes**

This file, on its own, doesn't do anything yet: Prometheus won't read it unless you tell it to explicitly, in two places.

**First, reference the file inside `prometheus.yml`:**
```bash
nano prometheus.yml
```
Add the `rule_files` line at the top, before `scrape_configs`:
```yaml
global:
  scrape_interval: 15s
rule_files:
  - "alert.rules.yml"
scrape_configs:
  - job_name: "node"
    static_configs:
      - targets: ["<SERVER_IP>:9100"]
  - job_name: "kubernetes"
    static_configs:
      - targets: ["<SERVER_IP>:10250"]
```

**Second, mount the file inside the Prometheus container in `docker-compose.monitoring.yml`:**
```bash
nano docker-compose.monitoring.yml
```
Add the file to the `prometheus` service's `volumes` block:
```yaml
services:
  prometheus:
    image: prom/prometheus
    volumes:
      - "./prometheus.yml:/etc/prometheus/prometheus.yml"
      - "./alert.rules.yml:/etc/prometheus/alert.rules.yml"
    ports: ["9090:9090"]
```
→ Without this second change, `prometheus.yml` (inside the container) would point to an `alert.rules.yml` that doesn't exist on that filesystem — the file lives on your server, but Prometheus runs inside a container with its own isolated filesystem, so it needs this `volume` to see it.

**3. Restart the stack to apply the changes**

```bash
docker compose -f docker-compose.monitoring.yml up -d
```
→ Compose detects the config changes and recreates the `prometheus` container with the new volumes mounted.

**4. Verify the rules loaded correctly**

In your browser:
```
http://<SERVER_IP>:9090/rules
```
→ Should list both alerts (`DiskFull`, `HighCPU`) under the `node-alerts` group, with status `inactive` (normal if the conditions aren't being met yet) or `firing` (if they are).

**Fix if the `/rules` page comes up empty:**
```bash
docker compose -f docker-compose.monitoring.yml logs prometheus | grep -i error
```
→ Look for YAML parsing errors (same kind of indentation problem you already saw in `compose.yaml`) or "file not found" errors if the volume wasn't mounted correctly.

**5. Test an alert actually firing**

The real alerts (`DiskFull` at 15%, `HighCPU` at 85%) can take a while to trigger in a quiet lab — to *see* the full cycle of an alert without waiting for the disk to nearly fill up, add one temporarily with a ridiculously low threshold, almost guaranteed to match:

```bash
nano alert.rules.yml
```
Add a third test alert to the same group:
```yaml
groups:
  - name: node-alerts
    rules:
      - alert: DiskFull
        expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 < 15
        for: 5m
        labels: {severity: critical}
        annotations: {summary: "Less than 15% disk free on {{ $labels.instance }}"}

      - alert: HighCPU
        expr: 100 - (avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 85
        for: 10m
        labels: {severity: warning}

      - alert: AlwaysOnTest
        expr: up == 1
        for: 10s
        labels: {severity: info}
        annotations: {summary: "Test alert — fires whenever the target is UP"}
```
→ `up == 1` is an internal Prometheus metric that's `1` while the target is being scraped correctly (`node_exporter` responding) — almost always true in an active lab, so this alert fires predictably. `for: 10s` (instead of minutes) makes it go to `firing` almost immediately, instead of waiting.

**Apply the change:**
```bash
docker compose -f docker-compose.monitoring.yml up -d
```
→ Remember: this recreates the Prometheus container so it reloads the mounted file.

**Watch it go through the three states, live:**
```
http://<SERVER_IP>:9090/alerts
```
→ (Note: it's `/alerts`, different from `/rules` in step 4 — `/rules` shows the *defined* rules, `/alerts` shows their *current evaluation state*). Reload the page every few seconds and you'll see `AlwaysOnTest` progress:
1. **`inactive`** (gray) — the condition (`up == 1`) hasn't evaluated as true yet, or just started being met and the `for:` time hasn't passed.
2. **`pending`** (yellow) — the condition is already true, but the `10s` from `for:` haven't passed yet — Prometheus waits to confirm it's not a momentary spike (same concept you already saw with `for: 5m` in `DiskFull`).
3. **`firing`** (red) — the `10s` passed with the condition sustained; the alert is truly active.

**Why the `alert.rules.yml` alert doesn't show up in `Grafana → Alerting → Alert rules`**

This is expected, not an error: by default, Grafana's **Alert rules** section only lists alerts **created inside Grafana** (called "Grafana-managed"). The rules you defined in `alert.rules.yml` live and get evaluated **inside Prometheus** — Grafana would only show them there if you specifically configure that data source as an "external alert source" (Mimir/Loki/Prometheus Alerting), an extra step we didn't cover in section 7.2. To visualize an alert directly in the Grafana UI, the simplest thing is to create a **native Grafana Alert Rule** that queries Prometheus — which is exactly what you're already doing by using it as a data source.

**Create a Grafana Alert Rule, step by step:**

**1. Go to Grafana's alerting section**
```
Side menu → Alerting → Alert rules → New alert rule
```

**2. Define the query**
- In **"1. Define query"**, select the **Prometheus** data source you already configured (section 7.2, step 5).
- In the query field, type the same test metric used in `alert.rules.yml`:
  ```
  up
  ```
  → Simple, and always has data if `node_exporter` is being scraped.

**3. Define the condition**
- In **"2. Define alert condition"**, Grafana automatically adds a `Reduce` step (collapses the time series to a single value, e.g. `Last`) and a `Threshold` step.
- Set the threshold to: **`IS BELOW 1`** — this fires when `up` stops being `1` (the target stops responding), or to force it to always fire in the test, use **`IS ABOVE 0`** (if `up` is `1`, it's always greater than `0` — fires immediately, same as you did with `up == 1` in Prometheus).

**4. Configure how often it's evaluated**
- In **"3. Add folder and labels"**, create or select a folder (e.g. "Homelab").
- In **"4. Set evaluation behavior"**:
  - Evaluation group: create a new one, e.g. `node-checks`, with a `10s` evaluation interval (same spirit as the `for: 10s` from the Prometheus test).
  - **Pending period**: `0s` so it goes to `Firing` almost immediately in this test (in a real alert, you'd leave a few minutes, same as `for: 5m`/`10m` in `alert.rules.yml`).

**5. Save the rule**
```
Save rule and exit
```

**6. Watch it go through its states**
```
Grafana → Alerting → Alert rules
```
→ Now you'll see your rule listed, with its current status:
- **`Normal`** (green) — the condition isn't met.
- **`Pending`** (yellow) — the condition is met, waiting for the `pending period`.
- **`Firing`** (red) — active alert.

Click on the rule to see the history of state transitions and the exact value evaluated each cycle.

**7. (Optional) Add it to a dashboard**

You can add an "Alert list" panel type to any dashboard (including the 1860 you already imported) to see the status of your alerts alongside the other metrics:
```
Dashboard → Add → Visualization → panel type: "Alert list"
```

**8. Cleanup — delete the test rule when you're done**
```
Grafana → Alerting → Alert rules → (select the rule) → Delete
```

**6. Remove the test alert in Prometheus once you've confirmed the full cycle**

```bash
nano alert.rules.yml
```
→ Delete the `AlwaysOnTest` block (has no real value in production, it was only to verify the alerting mechanism works end to end) and reapply:
```bash
docker compose -f docker-compose.monitoring.yml up -d
```

---

## Final Validation Checklist

```bash
sudo ufw status verbose          # firewall active and rules correct
sudo systemctl status fail2ban   # brute-force protection active
sudo systemctl status docker     # docker running
kubectl get nodes                # k3s cluster "Ready"
docker ps                        # expected containers running
curl localhost:9090/-/healthy    # Prometheus OK
curl localhost:9100/metrics | head -5  # node_exporter emitting data
```
→ Run this whole block after any major change. If something fails, it's your first diagnostic checkpoint.

---

## Suggested Next Steps (beyond this playbook)
- CI/CD (GitHub Actions/GitLab CI) for automatic build+push+deploy
- Alertmanager → Slack/PagerDuty for real notifications
- Automated backups with `restic` or `velero` (for k8s)
- TLS with Let's Encrypt (`certbot` or `cert-manager` in k8s)

---

## Guide: Publishing This Project on GitHub as a Portfolio

The goal isn't just to upload files — it's for a recruiter or hiring manager to understand your level in 30 seconds of scrolling. Structure and steps:

### 1. Recommended folder structure

```bash
mkdir -p sre-homelab-portfolio/{scripts,ansible,k8s,monitoring,docs}
cd sre-homelab-portfolio
```
```
sre-homelab-portfolio/
├── README.md                 ← the most important thing in the repo
├── incidents-sre-eng.md         ← your error log, referenced from the playbook
├── scripts/                  ← your .sh and .py files (backup.sh, healthcheck.py)
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
→ A repo organized by domain (not everything loose in the root) is the first signal of seniority a reviewer sees.

### 2. Initialize the repository

```bash
cd sre-homelab-portfolio
git init
git config user.name "Your Name"
git config user.email "you@email.com"
```
→ `git init` creates the local repository. `config` identifies your commits (mandatory the first time on a new server).

### 3. `.gitignore` — critical before the first commit

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
→ **Never upload secrets, logs, or generated binary files.** A leaked `.env` or `kubeconfig` on GitHub is a real security incident, not a cosmetic mistake.

### 4. Write the README (this is what actually gets you evaluated)

```bash
nano README.md
```

Minimum structure it should have:

```markdown
# SRE Homelab — Ubuntu + Docker + K8s + Ansible + Monitoring

Personal lab project implementing a complete SRE stack from scratch:
server hardening, containers, orchestration, infrastructure
automation, and observability.

## Stack
- Ubuntu Server 22.04/24.04
- Bash + Python (automation)
- Docker / Docker Compose
- Kubernetes (k3s)
- Ansible (IaC)
- Prometheus + Grafana + node_exporter

## Architecture
[diagram or description of how the pieces connect]

## How to run it
```bash
git clone https://github.com/yourusername/sre-homelab-portfolio
cd sre-homelab-portfolio
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml --check
```

## Documented incidents
See [incidents-sre-eng.md](incidents-sre-eng.md) — a real log of errors
found and resolved during implementation.

## What I learned
[2-3 lines of concrete technical takeaways, not generic ones]
```
→ **Why the "Documented incidents" section matters so much**: anyone can copy commands from a tutorial. Documenting real errors and how you diagnosed them demonstrates troubleshooting — which is literally an SRE's job. It's your strongest differentiator in a junior portfolio.

### 5. First commit

```bash
git add .
git status
```
→ **Always** check `git status` before `commit` — confirm no secret or generated file slipped through that `.gitignore` should have excluded.

```bash
git commit -m "Initial commit: base structure of the SRE homelab"
```

### 6. Create the repo on GitHub and push it

**Install the GitHub CLI first, if you don't have it:**
```bash
sudo apt install gh
gh --version
```
→ `gh` is the official GitHub CLI. Without this step, `gh auth login` and `gh repo create` fail with `command not found` — install it before continuing.

**Authenticate:**
```bash
gh auth login
```
→ Choose `GitHub.com` → `HTTPS` → `Login with a web browser` (gives you a one-time code to paste in the browser).

**Verify you're authenticated:**
```bash
gh auth status
```

**Create the remote repo and push, in one step:**
```bash
gh repo create sre-homelab-portfolio --public --source=. --remote=origin
```
→ Alternative without `gh`: create the repo manually on github.com and then:
```bash
git remote add origin https://github.com/yourusername/sre-homelab-portfolio.git
```

```bash
git branch -M main
git push -u origin main
```
→ `-u` sets `origin main` as the default target, so afterward you just use `git push`.

### 7. Final polish (what separates a "junior" repo from a "portfolio-ready" one)

- **Topics/tags on GitHub**: add `sre`, `devops`, `ansible`, `kubernetes`, `docker` in the repo settings (improves discoverability).
- **LICENSE**: add an MIT license (`gh repo edit --add-license mit` or from the UI) — shows professionalism.
- **Incremental commits, not one giant one**: if you keep working, commit per phase (`feat: add Prometheus monitoring`) — a readable commit history shows your way of working, not just the final result.
- **Architecture diagram**: a simple image (you can make it in [draw.io](https://draw.io) or with Mermaid directly in the README) is worth more than paragraphs of text.
- **Never upload real IPs, real domains, or credentials** — use placeholders (`<SERVER_IP>`) like in this very playbook.

```bash
git add incidents-sre-eng.md
git commit -m "docs: add incident log (14 cases, PHASE 2-4)"
git push
```
→ This is, in practice, what it looks like to document your learning as a real commit history.
