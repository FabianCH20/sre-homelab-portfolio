# Incident Log — SRE Homelab
🇪🇸 [Leer en español](incidentes-sre.md)
> Real errors found while practicing the [main playbook](./playbook-sre-ubuntu-server.md), documented in symptom → root cause → diagnosis → fix → lesson format. In SRE this is called an **incident runbook**: the goal is to never repeat the same investigation twice, and to demonstrate real troubleshooting, not just copying commands from a tutorial. Each incident includes references to official documentation and the GitHub repository of the tool involved, to dig deeper beyond the immediate fix.

---

## PHASE 2 — Bash

**Incident #1 — `Permission denied` when saving the script with `nano`**

- **Symptom**: `nano` won't let you save the file at `/opt/scripts/backup.sh`.
- **Root cause**: `/opt/scripts` belongs to `root` by default; the normal user has no write permission there.
- **Diagnosis**:
  ```bash
  ls -ld /opt/scripts
  ```
- **Fix applied**:
  ```bash
  sudo chown -R $USER:$USER /opt/scripts
  ```
  → One-off alternative: `sudo nano /opt/scripts/backup.sh` (but leaves the file owned by `root`, causing the same problem again later).
- **Lesson**: before working in a system directory (`/opt`, `/etc`, `/var`), check the owner with `ls -ld` first, don't assume permissions.
- **References**: Official — [GNU Coreutils Manual: chown/chmod](https://www.gnu.org/software/coreutils/manual/html_node/File-permissions.html) · GitHub — [man-pages (chown(1), ls(1))](https://github.com/mkerrisk/man-pages)

---

**Incident #2 — `unexpected EOF while looking for matching` when running the `if` block**

- **Symptom**: bash throws a syntax error and doesn't run the script.
- **Root cause**: the `if`/`fi` block was left incomplete when copying and pasting — the closing `fi` was missing, or a quote turned into a "curly" quote (`"`) from coming out of a rich-text editor instead of plain text.
- **Diagnosis**:
  ```bash
  cat -A backup.sh      # check for invisible/odd characters
  bash -n backup.sh     # validates syntax without running
  ```
- **Fix applied**: rewrite the block directly in `nano` instead of pasting it, making sure the closing `fi` and straight quotes (`"`, not `"`/`"`) are there.
- **Lesson**: **always run `bash -n script.sh` before `./script.sh`** — catches syntax errors with no side effects.
- **References**: Official — [GNU Bash Reference Manual: Conditional Constructs](https://www.gnu.org/software/bash/manual/html_node/Conditional-Constructs.html) · GitHub — [ShellCheck Wiki](https://github.com/koalaman/shellcheck/wiki)

---

**Incident #3 — `tar`: `Cannot stat: no such file or directory` + `Permission denied` + false success message**

- **Symptom**:
  ```
  tar: /etc/nginx: Cannot stat: no such file or directory
  tar (child): /var/backups/backup.tar.gz: Cannot open: Permission denied
  backup completed
  ```
- **Root cause** (two simultaneous problems):
  1. `/etc/nginx` didn't exist because nginx wasn't installed — the example path didn't apply to this server.
  2. `/var/backups` belongs to `root`; with no write permission, `tar` couldn't create the destination file.
  3. **A more serious silent problem**: the script printed `"backup completed"` even though `tar` failed — because it lacked `set -euo pipefail`, so bash kept running after the error.
- **Diagnosis**:
  ```bash
  ls /etc/nginx           # confirms whether the source path exists
  ls -ld /var/backups     # confirms the destination directory's owner
  ```
- **Fix applied**:
  ```bash
  sudo chown -R $USER:$USER /var/backups
  ```
  plus changing the source path to one that actually existed (`/etc/hostname`), and adding `set -euo pipefail` at the start of the script so it stops on the first real failure instead of continuing and reporting false success.
- **Lesson**: a script without `set -euo pipefail` can fail silently and report success. This header isn't optional in production scripts — it's the difference between a visible failure and a corrupted backup nobody notices until it needs to be restored.
- **References**: Official — [GNU Bash Manual: The Set Builtin](https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html) · GitHub — [ShellCheck Wiki: SC2312 (set -e pitfalls)](https://github.com/koalaman/shellcheck/wiki/SC2312)

---

**Incident #4 — `syntax error near unexpected token '('` when using `exec > >(tee -a "$LOGFILE") 2>&1`**

- **Symptom**:
  ```
  syntax error near unexpected token `('
  ```
- **Root cause**: the script was run with `sh backup.sh` instead of `bash backup.sh` (or `./backup.sh`). On Ubuntu, `sh` is actually `dash`, a simpler shell that **doesn't support** *process substitution* (`>(...)` / `<(...)`) — bash-exclusive syntax used in `exec > >(tee -a "$LOGFILE") 2>&1`.
- **Diagnosis**:
  ```bash
  head -1 backup.sh   # confirms the shebang is #!/usr/bin/env bash
  ```
  → If the shebang is correct but the error persists, the problem is how the script was invoked (with explicit `sh`), not the file itself.
- **Fix applied**: run it with `bash backup.sh` or `./backup.sh` (never `sh backup.sh`) when the script uses bash-specific syntax.
- **Lesson**: the shebang (`#!/usr/bin/env bash`) is only honored if you run the script as `./script.sh`. If someone else (or a cron job, a CI) invokes it with `sh script.sh`, the shebang is ignored and the shell used is `dash` — much more limited.
- **References**: Official — [GNU Bash Manual: Process Substitution](https://www.gnu.org/software/bash/manual/html_node/Process-Substitution.html) · GitHub — [ShellCheck Wiki: SC2039 (bashisms used with sh/dash)](https://github.com/koalaman/shellcheck/wiki/SC2039)

---

**Incident #5 — `syntax error near unexpected token '('` with correct `bash` — misplaced space**

- **Symptom**: same error message as Incident #4, but this time already correctly running with `bash`.
  ```
  backup.sh: line 5: syntax error near unexpected token `('
  ```
- **Root cause**: line 5 had a shifted space:
  ```bash
  exec >> (tee -a "$LOGFILE") 2>&1     # ❌ incorrect
  ```
  instead of:
  ```bash
  exec > >(tee -a "$LOGFILE") 2>&1     # ✅ correct
  ```
  `>> (...)` is interpreted as an append redirection (`>>`) followed by a loose subshell — invalid syntax there. `> >(...)` is *process substitution*: a normal `>` redirection followed by `>(...)`, with no space between `>` and `(`.
- **Diagnosis**:
  ```bash
  sed -n '5p' backup.sh       # prints only line 5 for inspection
  cat -A backup.sh | sed -n '5p'   # checks for invisible characters
  bash -n backup.sh           # validates syntax without running
  ```
- **Fix applied**: correct the line to `exec > >(tee -a "$LOGFILE") 2>&1`, with no space between the `>` and the `>(`.
- **Lesson**: in bash syntax, the exact position of spaces in redirection operators completely changes the meaning (`>>` append vs `> >(` process substitution). A single misplaced character produces a syntax error that doesn't say "you have an extra space" — you have to inspect the exact line with `sed -n 'Np'` to spot it.
- **References**: Official — [GNU Bash Manual: Redirections](https://www.gnu.org/software/bash/manual/html_node/Redirections.html) · GitHub — [ShellCheck Wiki (rule index)](https://github.com/koalaman/shellcheck/wiki/Checks)

---

**Incident #6 — `Permission denied` on `/var/log/chrony`, `/var/log/private`, etc. when compressing logs**

- **Symptom**:
  ```
  gzip: /var/log/landscape/sysinfo.log.gz: Permission denied
  find: '/var/log/chrony': Permission denied
  gzip: /var/log/bootstrap.log.gz: Permission denied
  find: '/var/log/private': Permission denied
  ```
- **Root cause**: `/var/log` contains subdirectories for system services (`chrony`, `landscape`, `private`, etc.) owned by `root` or specific system users. The script line:
  ```bash
  find /var/log -name "*.log" -mtime +30 -exec gzip {} \;
  ```
  didn't have privileges to write/compress there. Running `sudo bash backup.sh` "fixed" the symptom but elevated **the entire script** unnecessarily — bad practice, since other lines in the script don't need root.
- **Diagnosis**:
  ```bash
  ls -ld /var/log/chrony /var/log/private   # confirms the real owner of those directories
  grep -n "find /var/log" backup.sh          # confirms whether the line has sudo or not
  ```
- **Fix applied — surgical sudo**: instead of prepending `sudo` to the entire script invocation, `sudo` was added only to the line that needs it:
  ```bash
  sudo find /var/log -name "*.log" -mtime +30 -exec gzip {} \;
  ```
  The rest of the script keeps running as the normal user.
- **Lesson**: when only part of a script needs elevated privileges, `sudo` should be applied to that specific line, not to the whole script run — the principle of least privilege applied at the line level, not just the user level.
- **References**: Official — [sudoers(5) Manual (sudo.ws)](https://www.sudo.ws/docs/man/sudoers.man/) · GitHub — [sudo-project/sudo](https://github.com/sudo-project/sudo)

---

## PHASE 3 — Python

**Incident #7 — `SyntaxError: expected ':'` in the `check_endpoint` definition**

- **Symptom**:
  ```
  File "/opt/scripts/healtcheck.py", line 7
  def check_endpoint(url: str, timeout: int = 5) -> bool;
  SyntaxError: expected ':'
  ```
- **Root cause**: `;` (semicolon) was used instead of `:` (colon) at the end of the function definition. In Python, `:` is what opens the code block for a function, `if`, `for`, `class`, etc. — equivalent to `{` in other languages.
- **Diagnosis**:
  ```bash
  python3 -m py_compile /opt/scripts/healtcheck.py   # validates syntax without running
  ```
- **Fix applied**: change `def check_endpoint(...) -> bool;` to `def check_endpoint(...) -> bool:`.
- **Additional note**: the file had a typo in its name (`healtcheck.py` instead of `healthcheck.py`) — fixed with `mv` so it would match the references used in cron/systemd later in the playbook.
- **Lesson**: `python3 -m py_compile file.py` is the equivalent of `bash -n script.sh` — validates syntax with no side effects.
- **References**: Official — [Python Language Reference: Compound Statements](https://docs.python.org/3/reference/compound_stmts.html) · GitHub — [python/cpython](https://github.com/python/cpython)

---

**Incident #8 — `SyntaxError` in `if__name= "__main__":`**

- **Symptom**:
  ```
  line 16
  if__name= "__main__":
  ```
- **Root cause**: two errors combined on the same line:
  1. The space was missing between `if` and `__name__`, so Python interpreted `if__name` as a single identifier instead of the `if` keyword followed by the `__name__` variable.
  2. An underscore was missing (`__name__` has double underscores before and after) and `=` (assignment) was used instead of `==` (comparison).
- **Diagnosis**:
  ```bash
  python3 -m py_compile /opt/scripts/healthcheck.py
  ```
- **Fix applied**: correct it to the standard form: `if __name__ == "__main__":`.
- **Lesson**: `__name__` is a special variable Python defines in every module (it's `"__main__"` only if the file is run directly, not if it's imported). When retyping code by hand, it's easy to drop an underscore or merge them incorrectly — better to copy code directly than rewrite it from memory.
- **References**: Official — [Python Docs: `__main__` — Top-level script environment](https://docs.python.org/3/library/__main__.html) · GitHub — [python/cpython](https://github.com/python/cpython)

---

**Incident #9 — `error: externally-managed-environment` when running `pip install requests`**

- **Symptom**:
  ```
  error: externally-managed-environment
  This environment is externally managed
  To install Python packages system-wide, try apt install python3-xyz
  ```
- **Root cause**: `pip install requests` was run **without activating the venv first**, so it pointed at the system Python. Ubuntu 23.04+/24.04 blocks installing packages with `pip` directly to the system (PEP 668).
- **Diagnosis**:
  ```bash
  which pip   # should show /opt/venvs/ops/bin/pip if the venv is active
  ```
- **Fix applied**:
  ```bash
  source /opt/venvs/ops/bin/activate
  pip install requests
  ```
- **Lesson**: the terminal prompt shows a prefix like `(ops)` when the venv is active — a quick visual cue to confirm which environment you're installing into.
- **References**: Official — [PEP 668 – Marking Python base environments as "externally managed"](https://peps.python.org/pep-0668/) · GitHub — [pypa/pip issue #11530 (origin of this message)](https://github.com/pypa/pip/issues/11530)

---

**Incident #10 — `PermissionError: [Errno 13] Permission denied` in `site-packages` when installing inside the activated venv**

- **Symptom**:
  ```
  ERROR: Could not install packages due to an OSError: [Errno 13] Permission denied:
  '/opt/venvs/ops/lib/python3.14/site-packages/urllib3'
  ```
- **Root cause**: the venv had originally been created with `sudo` (or inside an `/opt` owned by `root`), so even though the venv was correctly activated this time, the normal user had no write permission over `site-packages` — same underlying pattern as Incident #1, but affecting the whole venv.
- **Diagnosis**:
  ```bash
  ls -ld /opt/venvs/ops
  ls -la /opt/venvs/ops/lib/python3.14/site-packages/ | head
  ```
- **Fix applied**:
  ```bash
  sudo chown -R $USER:$USER /opt/venvs/ops
  ```
  → Cleaner alternative: `chown` the parent directory (`/opt/venvs`) once, and create the venv afterward WITHOUT sudo.
- **Lesson**: permission issues in `/opt` are recurring in this playbook because `/opt` belongs to `root` by default. Repeating pattern: **check the owner with `ls -ld` before creating or writing anything there**.
- **References**: Official — [Python Docs: venv — Creation of virtual environments](https://docs.python.org/3/library/venv.html) · GitHub — [python/cpython (Lib/venv)](https://github.com/python/cpython/tree/main/Lib/venv)

---

**Incident #11 — `bad minute` / `errors in crontab file, can't install` when loading a cronjob from a file**

- **Symptom**:
  ```
  "/opt/scripts/cron/healthcheck.cron":2 bad minute
  errors in crontab file, can't install
  ```
- **Root cause** (two problems combined in the `.cron` file):
  1. The cronjob ended up **split across two lines** instead of one — cron requires the whole command to be on a single line. The "bad minute" message was a symptom of that split, not of an invalid character in the minute field itself.
  2. The command `crontab /opt/scripts/cron/healthcheck.cron` (used from the terminal to *load* the file) had accidentally been pasted **inside** the `.cron` file itself, as one more line.
- **Diagnosis**:
  ```bash
  cat -n /opt/scripts/cron/healthcheck.cron   # numbers lines, reveals the split and the extra line
  file /opt/scripts/cron/healthcheck.cron      # rules out CRLF/line-ending issues
  cat -A ... | sed -n '2p'                     # rules out invisible characters on that specific line
  ```
- **Fix applied**: rewrite the whole file with the cronjob on a single line and without the `crontab ...` command pasted inside.
- **Lesson**: when a cron error message points to a specific field but the field looks correct at a glance, review the **whole** file with line numbers (`cat -n`) before focusing only on the flagged line.
- **References**: Official — [crontab(5) — Linux man-pages (man7.org)](https://man7.org/linux/man-pages/man5/crontab.5.html) · GitHub — [cronie-crond/cronie](https://github.com/cronie-crond/cronie)

---

## PHASE 4 — Docker

**Incident #12 — persistent `permission denied` connecting to the Docker socket, even after `newgrp docker`**

- **Symptom**: `Permission denied while trying to connect to the Docker daemon socket at unix:///var/run/docker.sock`, and `newgrp docker` asked for a password and failed the same way.
- **Root cause**: the original `usermod -aG docker opsuser` had been applied to a user (`opsuser`) different from the one actually being used in the active session (another user, e.g. `ops` or the real login user). The user in use had never really been added to the `docker` group at the system level — that's why `newgrp` (which only loads the group into the session, doesn't assign it) failed asking for a group password that doesn't exist.
- **Diagnosis**:
  ```bash
  whoami
  groups $(whoami)
  getent group docker   # confirms which users actually belong to the group
  ```
- **Fix applied**:
  ```bash
  sudo usermod -aG docker <actual_user_in_use>
  exit   # log out completely — newgrp is NOT enough after a usermod
  # log back in
  groups   # confirm "docker" now appears
  ```
- **Lesson**: `newgrp` only reloads groups already assigned in the current session; if the user was never added to the group at the system level, `newgrp` will fail asking for a password. Always confirm `whoami` before diagnosing group issues — it's easy to lose track of which system user you're actually working as, especially if you switched between several users during the session.
- **References**: Official — [Docker Docs: Linux post-installation steps](https://docs.docker.com/engine/install/linux-postinstall/) · GitHub — [moby/moby](https://github.com/moby/moby)

---

**Incident #13 — `Unable to locate package docker-compose-plugin` / `docker: 'compose' is not a docker command`**

- **Symptom**:
  ```
  Error: Unable to locate package docker-compose-plugin
  ```
  and later, when trying to use it:
  ```
  docker: 'compose' is not a docker command
  ```
- **Root cause**: Docker's official repository (`download.docker.com`) wasn't registered in `apt`'s sources. This happens when Docker was installed through a method that doesn't configure that repo (or the repo-configuration step failed silently), leaving `apt` unable to find `docker-compose-plugin`, which doesn't exist in Ubuntu's standard repositories.
- **Diagnosis**:
  ```bash
  ls /etc/apt/sources.list.d/docker.* 2>/dev/null || echo "The Docker repo doesn't exist"
  dpkg -l | grep docker   # confirms which Docker packages are actually installed
  ```
- **Fix applied**: a clean full reinstall of Docker from the official repository via `apt` (see the from-scratch install section in the main playbook), which correctly registers the repo and installs `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, and `docker-compose-plugin` together in one flow — instead of installing Docker one way and the Compose plugin separately with a standalone `apt install docker-compose-plugin`, which failed because the repo was never registered.
- **Lesson**: when a specific package for a tool that "should come bundled" with another already-installed tool is missing (like Compose with Docker), suspect first that the source repository isn't configured, instead of assuming the package name is misspelled. `ls /etc/apt/sources.list.d/docker.*` is the first place to confirm it (the file may be called `docker.list` in the classic format or `docker.sources` in the current deb822 format).
- **References**: Official — [Docker Docs: Install Docker Compose (Linux)](https://docs.docker.com/compose/install/linux/) · GitHub — [docker/compose](https://github.com/docker/compose)

---

**Incident #14 — `-bash: EOF: Permission denied` when using a heredoc (`<<EOF`) to register the Docker repo**

- **Symptom**:
  ```
  -bash: EOF: Permission denied
  ```
  when trying to create `/etc/apt/sources.list.d/docker.sources` with a `sudo tee ... <<EOF ... EOF` block.
- **Root cause**: the heredoc broke halfway through — the closing `EOF` line didn't exactly match what bash expected (extra spaces, an altered line break from pasting the block). When that happens, bash never recognizes the heredoc's closing, and ends up interpreting the standalone word `EOF` as if it were a command to run — hence the `Permission denied`, likely from a file named `EOF` with no execute permission in the current directory.
- **Diagnosis**: check whether a stray `EOF` file was left in the working directory, and confirm the state of the half-created destination file:
  ```bash
  ls -la EOF 2>/dev/null
  cat /etc/apt/sources.list.d/docker.sources 2>/dev/null
  ```
- **Fix applied**: clean up the leftovers (`rm -f EOF`, delete the incomplete `.sources` file) and rewrite the full heredoc, making sure the closing `EOF` line is **completely alone**, with no spaces before or after. When typing interactively in the terminal (instead of pasting the whole block at once), the prompt changes to `>` while the heredoc stays open — that visually confirms it hasn't closed yet, and returns to a normal `$` once it does close correctly.
- **Lesson**: heredocs are fragile when pasting full multiline blocks, because any alteration to the closing line (even an invisible space) makes bash never recognize the end of the block. For single-line commands with variables, the `echo "..." | sudo tee file` form is less prone to this kind of breakage than a heredoc; for real multiline content (like the `.sources` format), the heredoc is necessary, but it's worth typing at least the closing line by hand instead of relying on exact pasting.
- **References**: Official — [GNU Bash Manual: Here Documents](https://www.gnu.org/software/bash/manual/html_node/Here-Documents.html) · GitHub — [ShellCheck Wiki](https://github.com/koalaman/shellcheck/wiki)

---

## PHASE 5 — Kubernetes

**Incident #15 — `bind: address already in use` when running `kubectl port-forward`**

- **Symptom**:
  ```
  Unable to listen on port 8080: Listeners failed to create with the following errors:
  [unable to create listener: Error listen tcp4 127.0.0.1:8080: bind: address already in use
   unable to create listener: Error listen tcp6 [::1]:8080: bind: address already in use]
  error: unable to listen on any of the requested ports: [{8080 8080}]
  ```
  when running `kubectl port-forward myapp-7cd5b58c94-8lvpv 8080`.
- **Root cause** (two combined problems):
  1. The command was written with a single port number (`8080`) instead of the `<local-port>:<pod-port>` format. With a single number, `kubectl` tries to use that same port both on the host and inside the pod — but the pod (`nginx:latest`) listens on port 80, not 8080, so the correct format was `8080:80`.
  2. Even after fixing the format, local port 8080 was already **occupied by another process on the server** — the `bind: address already in use` is an OS-level port conflict, unrelated to Kubernetes. Very likely the Docker `nginx-test` container or the WordPress stack (both used in earlier phases) were still running and also mapped to 8080.
- **Diagnosis**:
  ```bash
  sudo ss -tlnp | grep 8080   # confirms which process is already listening on that port
  docker ps                    # checks whether a Docker container is still mapped to 8080
  ```
- **Fix applied**: use a different local port for the `port-forward`, which doesn't need to match the pod's port:
  ```bash
  kubectl port-forward myapp-7cd5b58c94-8lvpv 8081:80
  curl http://localhost:8081
  ```
  → Alternative: free up 8080 by stopping the Docker container that was using it (`docker stop nginx-test`) before repeating the original `port-forward`.
- **Lesson**: `kubectl port-forward` competes for host ports exactly like any other process — there's no special isolation just because it comes from Kubernetes. Before assuming a port is free, it's worth checking what else was left running from earlier phases or tests (Docker, Compose, etc.) on the same server.
- **References**: Official — [Kubernetes Docs: kubectl port-forward reference](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#port-forward) · GitHub — [kubernetes/kubernetes](https://github.com/kubernetes/kubernetes) (install used: [k3s-io/k3s](https://github.com/k3s-io/k3s))

---

## PHASE 6 — Ansible

**Incident #16 — `ansible-playbook` hangs at `TASK [Gathering Facts]` with no progress**

- **Symptom**: the command `ansible-playbook -i inventory.ini playbook.yml --check` prints `PLAY [web]` and `TASK [Gathering Facts]`, and just stays there indefinitely with no visible error or progress.
- **Root cause**: with `ansible_connection=local`, the playbook's `become: true` task needs to elevate to `sudo` in the current session. If the user requires a password for `sudo` (no `NOPASSWD` configured), Ansible sits waiting for that password — but the prompt isn't always visible in normal mode, giving the impression the command is "hung" with no further information.
- **Diagnosis**:
  ```bash
  ansible-playbook -i inventory.ini playbook.yml --check -vvv
  ```
  → Verbose mode (`-vvv`) exposes the exact point where it's stuck, including whether it's waiting for the `sudo` password.
- **Fix applied**: use the flag that makes the password prompt visible:
  ```bash
  ansible-playbook -i inventory.ini playbook.yml --check --ask-become-pass
  ```
  → With this, Ansible explicitly shows `BECOME password:` and continues normally after you enter it.
- **Lesson**: when an Ansible task uses `become: true` and the user doesn't have passwordless `sudo` configured, the command needs `--ask-become-pass` (or `--ask-become-pass` together with `--ask-pass` if it also applies to the connection) — otherwise, the command looks frozen instead of failing with a clear error.
- **References**: Official — [Ansible Docs: Understanding privilege escalation (become)](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_privilege_escalation.html) · GitHub — [ansible/ansible](https://github.com/ansible/ansible)

---

**Incident #17 — `Could not find or access 'app.env.j2'` in the `template` module task**

- **Symptom**:
  ```
  Could not find or access 'app.env.j2'
  Searched in:
      /opt/ansible/templates/app.env.j2
      /opt/ansible/app.env.j2
  ```
  with `PLAY RECAP` showing `ok=4 changed=1 ... failed=1` — meaning the earlier playbook tasks (updating packages, installing Docker, enabling the service) had run successfully; only the last task (`Copy app config`, using the `template` module) failed.
- **Root cause**: `app.env.j2` was an example filename in the generic playbook — the real file was never created. Ansible's `template` module requires the source file to physically exist in a `templates/` folder next to the playbook before it can copy it (with Jinja2 variable substitution) to the destination.
- **Diagnosis**: the error message itself already indicates the exact paths where Ansible looked for the file and didn't find it — confirming the problem is the file's absence, not a playbook syntax error (the earlier tasks ran fine).
- **Fix applied**: create the missing template file:
  ```bash
  mkdir -p /opt/ansible/templates
  nano /opt/ansible/templates/app.env.j2
  ```
  with content using Jinja2 syntax for dynamic variables, e.g.:
  ```
  APP_ENV=production
  APP_DEBUG=false
  DB_HOST={{ ansible_default_ipv4.address | default('localhost') }}
  ```
  After creating the file, `ansible-playbook -i inventory.ini playbook.yml --check --ask-become-pass` passed with no error.
- **Lesson**: Ansible's `template` module looks for the source file in a `templates/` folder relative to the playbook by convention — a playbook can be syntactically valid and run several tasks successfully, and still fail on a specific task simply because a referenced support file was never created. The `PLAY RECAP` (`ok=X changed=Y failed=Z`) is the quick way to confirm how much of the playbook did apply before the failure point.
- **References**: Official — [ansible.builtin.template module docs](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/template_module.html) · GitHub — [ansible/ansible](https://github.com/ansible/ansible)

---

**Incident #18 — `Cannot create container when image is not specified!` in the `docker_container` handler**

- **Symptom**:
  ```
  fatal: [srv-prod-01]: FAILED! => {
      "changed": false,
      "msg": "Cannot create container when image is not specified!"
  }
  PLAY RECAP: ok=5 changed=2 ... failed=1
  ```
- **Root cause**: the `restart app` handler used the `docker_container` module with `name: myapp` and `restart: true`, but **without the `image:` key**. Since the `myapp` container didn't exist yet (never created with `docker run` or another Ansible task), the module tried to create it from scratch — and to create a Docker container you need to know which image to use. The handler only fired for the first time because the `template` task from Incident #17 (just fixed) reported a real change (`notify: restart app`), triggering the handler for the first time in this session.
- **Diagnosis**: the `PLAY RECAP` (`ok=5 changed=2 ... failed=1`) confirmed all earlier tasks ran fine — the failure was isolated to the handler, and the `msg` itself names the exact cause.
- **Fix applied**: add the `image:` key to the handler:
  ```yaml
  handlers:
    - name: restart app
      docker_container:
        name: myapp
        image: nginx:latest
        state: started
        restart: true
  ```
  → `nginx:latest` (the same real public image already used in Docker and Kubernetes) was used instead of `myapp:1.0`, which was never built — same pattern as the `ErrImagePull` seen in Kubernetes Incident #15.
- **Lesson**: Ansible's `docker_container` module needs an explicit `image:` in order to create a container that doesn't exist yet — omitting it doesn't fail during playbook syntax validation, only when the real task runs. Handlers, since they fire conditionally (only if something changed), can hide configuration errors across several runs until they finally trigger for the first time.
- **References**: Official — [community.docker.docker_container module docs](https://docs.ansible.com/projects/ansible/latest/collections/community/docker/docker_container_module.html) · GitHub — [ansible-collections/community.docker](https://github.com/ansible-collections/community.docker)

---

**Incident #19 — `Destination directory /opt/app does not exist` in the `template` module task**

- **Symptom**:
  ```
  fatal: [srv-prod-01]: FAILED! => {
      "changed": false,
      "msg": "Destination directory /opt/app does not exist"
  }
  PLAY RECAP: ok=4 changed=0 ... failed=1
  ```
- **Root cause**: the `Copy app config` task uses `template` with `dest: /opt/app/.env`, but the `/opt/app` directory was never created. Ansible's `template` module **does not create intermediate directories automatically** — unlike `mkdir -p` in bash, it expects the destination to already exist.
- **Diagnosis**: the error message is already explicit about the cause (`Destination directory ... does not exist`); no additional diagnosis was needed beyond confirming that `/opt/app` indeed didn't exist.
- **Fix applied**: add a `file` task with `state: directory` before the `template` task:
  ```yaml
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
  ```
- **Lesson**: unlike modules such as `copy` or shell tools with `-p` (auto-create parents), Ansible's `template` module is strict about the destination directory already existing. It's good practice to explicitly declare directory creation with the `file` module (`state: directory`) as a separate task, before any task that writes files inside them — keeps the playbook idempotent and explicit about the state it expects to find.
- **References**: Official — [ansible.builtin.file module docs](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/file_module.html) · GitHub — [ansible/ansible](https://github.com/ansible/ansible)

---

## PHASE 7 — Monitoring

**Incident #20 — `node_exporter: command not found` after an apparently successful download**

- **Symptom**: `node_exporter --version` returns `command not found`, despite having previously run the download and extraction block.
- **Root cause**: the earlier download attempt had silently failed due to an underlying issue (see the earlier Incident about the `node_exporter` URL with a stale hardcoded version, which downloaded a 404 HTML page instead of the real `.tar.gz`). On a later retry, the download and `tar xvf` did complete successfully — leaving the `node_exporter-1.12.1.linux-amd64/` folder with the binary inside — but the last step, `sudo mv .../node_exporter /usr/local/bin/`, never got run in that session. The binary existed on the server, just not in a path included in `PATH`.
- **Diagnosis**:
  ```bash
  ls -la ~ | grep node_exporter   # confirms whether the extracted folder exists
  ls -l ~/node_exporter-1.12.1.linux-amd64/   # confirms the binary is inside
  ```
- **Fix applied**: explicitly move the binary using the full path (avoiding the `node_exporter-*/` wildcard, more prone to ambiguity if leftovers from earlier attempts with different versions remain in the same directory):
  ```bash
  sudo mv ~/node_exporter-1.12.1.linux-amd64/node_exporter /usr/local/bin/
  node_exporter --version
  rm -rf ~/node_exporter-1.12.1.linux-amd64 ~/node_exporter-1.12.1.linux-amd64.tar.gz
  ```
- **Lesson**: when a multi-step install command gets interrupted (by an earlier error, or by cutting the session short), don't assume it "just doesn't work" in general — check step by step which individual steps actually completed (`ls -la` to confirm resulting files/folders) before repeating the entire install from scratch. In this case, only a `mv` was missing, not re-downloading anything.
- **References**: Official — [Prometheus Docs: Installation](https://prometheus.io/docs/prometheus/latest/installation/) · GitHub — [prometheus/node_exporter](https://github.com/prometheus/node_exporter)

---

**Incident #21 — `go-yaml load error in parser: did not find expected key` when adding a second volume in `docker-compose.monitoring.yml`**

- **Symptom**:
  ```
  go-yaml load error in parser (while parsing a block mapping) at L4.C5-L8.C6: did not find expected key
  ```
  when running `docker compose -f docker-compose.monitoring.yml up -d`.
- **Root cause**: while editing the file to add the second line of the `prometheus` service's `volumes:` block (also mounting `alert.rules.yml`, for the alerts section), the indentation became inconsistent between that list and the following keys (`ports:`, and the `grafana:` service below) — the same kind of breakage already seen earlier in `compose.yaml` (earlier WordPress + MariaDB incident), but this time in the monitoring file.
- **Diagnosis**:
  ```bash
  cat -n docker-compose.monitoring.yml   # checks indentation line by line
  cat -A docker-compose.monitoring.yml | sed -n '1,10p'   # rules out tabs mixed with spaces
  ```
- **Fix applied**: rewrite the whole file with consistent 2-space indentation at every level, typing it instead of pasting it all at once:
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
  and validating with `docker compose -f docker-compose.monitoring.yml config` before trying `up -d` again.
- **Lesson**: adding a single line to a YAML file that already worked is a common failure point — the new content can visually misalign the rest of the block without it being obvious at a glance in the editor. Validating with `docker compose config` (or the tool's equivalent) after **any** edit to an existing YAML, not just when creating it, avoids repeating the trial-and-error cycle on `up -d`.
- **References**: Official — [YAML Specification 1.2](https://yaml.org/spec/1.2.2/) · GitHub — [docker/compose](https://github.com/docker/compose)

---

## Cross-Cutting Patterns (for your README)

Across the 21 incidents, five root causes keep repeating — worth naming explicitly in your portfolio as evidence of real learning:

1. **Permissions on system directories** (`/opt`, `/var/log`) — because they belong to `root` by default. Appears in Incidents #1, #3, #6, #10. Cross-cutting lesson: check ownership with `ls -ld` **before** writing, not after failing.
2. **Unverified execution context** (which user? which shell? venv active? repo registered? what else is running on the server? does sudo need a password?) — before assuming a command "should just work". Appears in Incidents #4, #9, #12, #13, #15, #16. Cross-cutting lesson: confirming the exact context (`whoami`, `which`, `groups`, `ls /etc/.../docker.*`, `ss -tlnp`, `-vvv` mode) is faster than guessing from the error message.
3. **Multiline blocks broken by copy/paste or editing** (`if`/`fi`, cronjobs, heredocs, YAML) — an invisible character or a malformed indentation line produces confusing syntax errors that don't describe the real cause. Appears in Incidents #2, #11, #14, #21. Cross-cutting lesson: when a syntax error doesn't make sense at a glance, review the entire file with `cat -n` or `cat -A`, not just the line the message points to — and validate with the corresponding config-check tool (`bash -n`, `docker compose config`, etc.) after **any** edit, not just when creating the file.
4. **Declarative modules assuming unmet preconditions** (image not specified, destination directory missing, source file not created) — unlike imperative scripts, Ansible modules fail explicitly instead of improvising a default value. Appears in Incidents #17, #18, #19. Cross-cutting lesson: every declarative module (Ansible, Kubernetes, Compose) has its own implicit preconditions — read the specific module's official documentation before assuming behavior will be "like in bash".
5. **Multi-step installs interrupted halfway through** — an earlier step fails (the stale-URL incident) and the process gets picked back up later without re-checking which steps actually completed. Appears in Incident #20. Cross-cutting lesson: before repeating a full install from scratch, check with `ls -la` which artifacts already exist — maybe only the last step is missing, not the whole process.
