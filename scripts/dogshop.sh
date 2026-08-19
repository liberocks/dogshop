#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="dogshop"
NAMESPACE="dogshop"
DATADOG_NAMESPACE="datadog"
STATE_DIR="$ROOT/.state"
SHARED_ENV="$ROOT/.env"
MCP_SOURCE="$ROOT/sources/kubernetes-mcp-server"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

load_env() {
  # The local file is sourced without printing or copying its contents.
  [[ -f "$SHARED_ENV" ]] && source "$SHARED_ENV"
  DD_APPLICATION_ID="${DD_APPLICATION_ID:-${NEXT_PUBLIC_DD_APPLICATION_ID:-}}"
  DD_CLIENT_TOKEN="${DD_CLIENT_TOKEN:-${NEXT_PUBLIC_DD_CLIENT_TOKEN:-}}"
  : "${DD_API_KEY:?DD_API_KEY must be set in $SHARED_ENV}"
  : "${DD_APP_KEY:?DD_APP_KEY must be set in $SHARED_ENV}"
  : "${DD_APPLICATION_ID:?DD_APPLICATION_ID must be set in $ROOT/.env for browser RUM}"
  : "${DD_CLIENT_TOKEN:?DD_CLIENT_TOKEN must be set in $ROOT/.env for browser RUM}"
  DD_SITE="${DD_SITE:-${NEXT_PUBLIC_DD_SITE:-datadoghq.com}}"
  DD_ENV="${DD_ENV:-dogshop-minikube}"
  DD_VERSION="${DD_VERSION:-latest-pinned}"
  export DD_SITE DD_ENV DD_VERSION
}

kubectl_dogshop() {
  kubectl --context "$PROFILE" "$@"
}

ensure_context() {
  kubectl --context "$PROFILE" cluster-info >/dev/null || die "Minikube profile $PROFILE is not reachable; run make cluster first"
}

cluster() {
  need minikube
  need kubectl
  local previous_context
  previous_context="$(kubectl config current-context 2>/dev/null || true)"
  minikube start --profile "$PROFILE" --cpus=6 --memory=7168 --disk-size=30g
  minikube -p "$PROFILE" addons enable metrics-server
  if [[ -n "$previous_context" ]]; then
    kubectl config use-context "$previous_context" >/dev/null
  fi
  kubectl_dogshop get nodes
}

install_datadog() {
  need helm
  kubectl_dogshop get namespace "$DATADOG_NAMESPACE" >/dev/null 2>&1 || kubectl_dogshop create namespace "$DATADOG_NAMESPACE"
  helm repo add datadog https://helm.datadoghq.com >/dev/null 2>&1 || true
  helm repo update datadog >/dev/null
  helm upgrade --install datadog-operator datadog/datadog-operator \
    --kube-context "$PROFILE" \
    --namespace "$DATADOG_NAMESPACE" \
    --set resources.requests.cpu=50m \
    --set resources.requests.memory=128Mi \
    --set resources.limits.cpu=200m \
    --set resources.limits.memory=256Mi \
    --wait
  kubectl_dogshop wait --namespace "$DATADOG_NAMESPACE" --for=condition=Established \
    crd/datadogagents.datadoghq.com --timeout=120s
  kubectl_dogshop create secret generic dogshop-datadog \
    --namespace "$DATADOG_NAMESPACE" \
    --from-literal=api-key="$DD_API_KEY" \
    --from-literal=app-key="$DD_APP_KEY" \
    --dry-run=client -o yaml | kubectl_dogshop apply -f -
  envsubst < "$ROOT/manifests/datadog/datadog-agent.yaml" | kubectl_dogshop apply -f -
  kubectl_dogshop rollout status --namespace "$DATADOG_NAMESPACE" deployment/datadog-operator --timeout=180s
}

deploy() {
  load_env
  ensure_context
  install_datadog
  kubectl_dogshop apply -f "$ROOT/manifests/base/namespace.yaml"
  kubectl_dogshop create configmap dogshop-runtime \
    --from-literal=DD_SITE="$DD_SITE" \
    --from-literal=DD_ENV="$DD_ENV" \
    --from-literal=DD_VERSION="$DD_VERSION" \
    --namespace "$NAMESPACE" \
    --dry-run=client -o yaml | kubectl_dogshop apply -f -
  kubectl_dogshop create secret generic dogshop-rum \
    --from-literal=application-id="$DD_APPLICATION_ID" \
    --from-literal=client-token="$DD_CLIENT_TOKEN" \
    --namespace "$NAMESPACE" \
    --dry-run=client -o yaml | kubectl_dogshop apply -f -
  kubectl kustomize "$ROOT/manifests/base" | envsubst | kubectl_dogshop apply -f -
  kubectl_dogshop rollout status statefulset/postgres --namespace "$NAMESPACE" --timeout=10m
  kubectl_dogshop rollout status statefulset/redis --namespace "$NAMESPACE" --timeout=5m
  for deployment in backend worker ads discounts frontend service-proxy traffic; do
    kubectl_dogshop rollout status "deployment/$deployment" --namespace "$NAMESPACE" --timeout=10m
  done
  status
}

status() {
  ensure_context
  kubectl_dogshop get pods,services,pvc --namespace "$NAMESPACE"
  kubectl_dogshop get datadogagent --namespace "$DATADOG_NAMESPACE" 2>/dev/null || true
}

open() {
  ensure_context
  printf 'Dogshop is available at http://localhost:8080 while this command runs.\n'
  kubectl_dogshop port-forward --namespace "$NAMESPACE" service/service-proxy 8080:80
}

smoke() {
  ensure_context
  kubectl_dogshop run dogshop-smoke --namespace "$NAMESPACE" --rm -i --restart=Never \
    --image=curlimages/curl@sha256:94e9e444bcba979c2ea12e27ae39bee4cd10bc7041a472c4727a558e213744e6 --image-pull-policy=IfNotPresent \
    --command -- curl --fail --silent --show-error http://service-proxy/
}

fault() {
  ensure_context
  local scenario="${1:-}"
  case "$scenario" in
    service-selector)
      kubectl_dogshop apply -f "$ROOT/manifests/faults/service-selector.yaml"
      ;;
    invalid-image)
      kubectl_dogshop patch deployment/discounts --namespace "$NAMESPACE" --type=strategic --patch-file "$ROOT/manifests/faults/invalid-image.yaml"
      ;;
    invalid-readiness)
      kubectl_dogshop patch deployment/frontend --namespace "$NAMESPACE" --type=strategic --patch-file "$ROOT/manifests/faults/invalid-readiness.yaml"
      ;;
    *) die "scenario must be service-selector, invalid-image, or invalid-readiness" ;;
  esac
}

reset() {
  load_env
  ensure_context
  kubectl kustomize "$ROOT/manifests/base" | envsubst | kubectl_dogshop apply -f -
  kubectl_dogshop rollout restart deployment/frontend deployment/backend deployment/worker deployment/ads deployment/discounts deployment/service-proxy --namespace "$NAMESPACE"
}

mcp_config() {
  ensure_context
  [[ -d "$MCP_SOURCE" ]] || die "Kubernetes MCP source is not available at $MCP_SOURCE"
  mkdir -p "$STATE_DIR"
  kubectl_dogshop apply -f "$ROOT/manifests/base/namespace.yaml"
  kubectl_dogshop apply --namespace "$NAMESPACE" -f "$ROOT/manifests/base/mcp-rbac.yaml"
  kubectl_dogshop wait --namespace "$NAMESPACE" --for=create serviceaccount/dogshop-mcp --timeout=60s
  local token api_server ca_file
  token="$(kubectl_dogshop create token dogshop-mcp --namespace "$NAMESPACE" --duration=8h)"
  api_server="$(kubectl_dogshop config view --minify --raw -o jsonpath='{.clusters[0].cluster.server}')"
  ca_file="$(kubectl_dogshop config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority}')"
  [[ -n "$ca_file" && -r "$ca_file" ]] || die "Minikube CA file is not available for the restricted kubeconfig"
  kubectl config --kubeconfig="$STATE_DIR/dogshop-mcp.kubeconfig" set-cluster dogshop-minikube \
    --server="$api_server" --certificate-authority="$ca_file" --embed-certs=true >/dev/null
  kubectl config --kubeconfig="$STATE_DIR/dogshop-mcp.kubeconfig" set-credentials dogshop-mcp --token="$token" >/dev/null
  kubectl config --kubeconfig="$STATE_DIR/dogshop-mcp.kubeconfig" set-context dogshop-mcp \
    --cluster=dogshop-minikube --user=dogshop-mcp --namespace="$NAMESPACE" >/dev/null
  kubectl config --kubeconfig="$STATE_DIR/dogshop-mcp.kubeconfig" use-context dogshop-mcp >/dev/null
  chmod 600 "$STATE_DIR/dogshop-mcp.kubeconfig"
  (cd "$MCP_SOURCE" && go build -mod=readonly -o "$STATE_DIR/kubernetes-mcp-server" ./cmd/kubernetes-mcp-server)
  printf 'MCP server: cd %s && %s --config mcp/dogshop.toml\n' "$ROOT" "$STATE_DIR/kubernetes-mcp-server"
}

down() {
  ensure_context
  kubectl_dogshop delete namespace "$NAMESPACE" --ignore-not-found
}

destroy() {
  need minikube
  minikube delete --profile "$PROFILE"
}

validate() {
  need kubectl
  kubectl kustomize "$ROOT/manifests/base" >/dev/null
  kubectl kustomize "$ROOT/manifests/datadog" >/dev/null
  bash -n "$ROOT/scripts/dogshop.sh"
  printf 'Manifest and shell validation passed.\n'
}

help() {
  cat <<'EOF'
make cluster                 Create an isolated Minikube profile and enable metrics.
make deploy                  Install Datadog, deploy Dogshop, and start traffic.
make status                  Show Dogshop and Datadog resources.
make open                    Forward the storefront to http://localhost:8080.
make smoke                   Request the internal service proxy.
make mcp-config              Create limited kubeconfig and build the sibling MCP source.
make fault SCENARIO=<name>   Apply service-selector, invalid-image, or invalid-readiness.
make reset                   Restore the healthy base manifests.
make down                    Delete only the Dogshop namespace.
make destroy                 Delete only the Dogshop Minikube profile.
EOF
}

case "${1:-help}" in
  cluster) cluster ;;
  deploy) deploy ;;
  status) status ;;
  open) open ;;
  smoke) smoke ;;
  mcp-config) mcp_config ;;
  fault) fault "${2:-}" ;;
  reset) reset ;;
  down) down ;;
  destroy) destroy ;;
  validate) validate ;;
  help|-h|--help) help ;;
  *) die "unknown command: $1" ;;
esac
