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

## Stack

![Ubuntu](https://img.shields.io/badge/Ubuntu-E95420?style=for-the-badge&logo=ubuntu&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)
![Ansible](https://img.shields.io/badge/Ansible-EE0000?style=for-the-badge&logo=ansible&logoColor=white)
![Prometheus](https://img.shields.io/badge/Prometheus-E6522C?style=for-the-badge&logo=prometheus&logoColor=white)
![Grafana](https://img.shields.io/badge/Grafana-F46800?style=for-the-badge&logo=grafana&logoColor=white)

## Architecture

```mermaid
flowchart TD
    HOST["🖥️ Ubuntu Server (VirtualBox VM)"]
    H["🔒 Hardening<br/>SSH · UFW · Fail2ban"]
    B["🐍 Bash & Python<br/>Scripts · cron · venv"]
    AN["⚙️ Ansible<br/>Automates Docker"]
    D["🐳 Docker Engine<br/>nginx · mysql · wordpress"]
    K["☸️ Kubernetes k3s<br/>Deployment + Service"]
    NE["node_exporter<br/>host metrics"]
    P["Prometheus<br/>scrape + alert"]
    G["Grafana<br/>dashboards"]

    HOST --> H
    HOST --> B
    HOST --> AN
    HOST --> D
    HOST --> K
    D -->|metrics| NE
    K -->|metrics| NE
    NE --> P --> G

    classDef ctrl fill:#0c447c,color:#fff,stroke:#083258;
    classDef work fill:#5a50c4,color:#fff,stroke:#3c3489;
    classDef mon fill:#0f6e56,color:#fff,stroke:#04342c;
    class H,B,AN ctrl
    class D,K work
    class NE,P,G mon
```

## How to run it
```bash
git clone https://github.com/FabianCH20/sre-homelab-portfolio
cd sre-homelab-portfolio
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml --check
```

## Documented incidents
See [incidentes-sre.md](incidentes-sre.md) — a real log of errors
found and resolved during implementation.
