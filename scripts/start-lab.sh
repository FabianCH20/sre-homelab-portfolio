#!/usr/bin/env bash
# start-lab.sh — Levanta todo el homelab SRE con un solo comando
# Uso: ./start-lab.sh

set -uo pipefail
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[FAIL]${NC} $1"; }

echo "=== Levantando homelab SRE ==="
echo

# ---------- 1. Servicios de sistema ----------
echo "--- Servicios de sistema ---"

for svc in docker k3s node_exporter; do
  if systemctl is-active --quiet "$svc"; then
    log "$svc ya está activo"
  else
    warn "$svc no está activo, iniciando..."
    if sudo systemctl start "$svc" 2>/dev/null; then
      log "$svc iniciado"
    else
      err "$svc no se pudo iniciar (¿está instalado? revisa 'systemctl status $svc')"
    fi
  fi
done
echo

# ---------- 2. Stack de monitoreo (Prometheus + Grafana) ----------
echo "--- Monitoreo (Prometheus + Grafana) ---"

MONITORING_DIR="/opt/monitoring"
if [ -f "$MONITORING_DIR/docker-compose.monitoring.yml" ]; then
  cd "$MONITORING_DIR" || exit 1
  if docker compose -f docker-compose.monitoring.yml up -d; then
    log "Stack de monitoreo levantado desde $MONITORING_DIR"
  else
    err "Falló al levantar el stack de monitoreo"
  fi
else
  warn "No se encontró docker-compose.monitoring.yml en $MONITORING_DIR — se omite"
fi
echo

# ---------- 3. Otros proyectos de Docker Compose ----------
echo "--- Otros proyectos Docker Compose ---"

COMPOSE_PROJECTS=(
  "/opt/apps/compose-lab"
  "/opt/apps/db-stack"
)

for dir in "${COMPOSE_PROJECTS[@]}"; do
  if [ -f "$dir/compose.yaml" ] || [ -f "$dir/docker-compose.yml" ]; then
    cd "$dir" || continue
    if docker compose up -d; then
      log "Proyecto levantado: $dir"
    else
      err "Falló al levantar: $dir"
    fi
  fi
done
echo

# ---------- 4. Kubernetes (k3s) ----------
echo "--- Kubernetes (k3s) ---"

if command -v kubectl &> /dev/null; then
  if [ -f "/opt/k8s/deployment.yaml" ]; then
    if kubectl apply -f /opt/k8s/deployment.yaml; then
      log "Manifiesto de Kubernetes aplicado (/opt/k8s/deployment.yaml)"
    else
      err "Falló al aplicar el manifiesto de Kubernetes"
    fi
  else
    warn "No se encontró /opt/k8s/deployment.yaml — se omite"
  fi
else
  warn "kubectl no disponible en este PATH"
fi
echo

# ---------- 5. Resumen final ----------
echo "=== Resumen ==="
echo

echo "Contenedores Docker corriendo:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || warn "No se pudo consultar Docker"
echo

if command -v kubectl &> /dev/null; then
  echo "Pods de Kubernetes:"
  kubectl get pods 2>/dev/null || warn "No se pudo consultar k3s"
  echo
fi

IP=$(hostname -I | awk '{print $1}')
echo "=== Accesos ==="
echo "Prometheus:  http://${IP}:9090"
echo "Grafana:     http://${IP}:3000"
echo "node_exporter: http://${IP}:9100/metrics"
echo
echo "=== Listo ==="
