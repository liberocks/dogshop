# Dogshop Minikube Demonstration

Dogshop is an isolated Minikube deployment that runs the published Storedog
application images unchanged. It retains the application's browser-driven demo
traffic and Datadog instrumentation while providing a safe, repeatable workload
for the sibling Kubernetes MCP server.

Neither `sources/storedog` nor `sources/kubernetes-mcp-server` is modified by
this project. Dogshop's only source dependency is the MCP binary built into its
ignored `.state/` directory.

## Prerequisites

- Docker Desktop running
- `minikube`, `kubectl`, `helm`, `go`, and `envsubst`
- Datadog API and application keys in `.env` as `DD_API_KEY` and `DD_APP_KEY`
- RUM `DD_APPLICATION_ID` and `NEXT_PUBLIC_DD_CLIENT_TOKEN` values in `.env`

The lifecycle script sources `.env` only at command execution. It never
prints, copies, or commits its contents.

## Start

```bash
make cluster
make deploy
make open
```

`make cluster` creates only the `dogshop` Minikube profile with 6 CPUs, 7 GiB
of memory, 30 GiB of disk, and the Metrics API enabled. It restores the
previous active context; every lifecycle operation explicitly passes
`--context dogshop` so the prior active cluster cannot be mutated by mistake.

`make deploy` installs the Datadog Operator in `datadog`, creates credentials
from environment variables, deploys the `DatadogAgent`, then deploys Dogshop in
the `dogshop` namespace. The UI is intentionally exposed only with
`kubectl port-forward`, not host networking or an Ingress controller.

The first frontend startup compiles the published Next.js image in the pod and
can take several minutes on a local cluster. Later restarts use the existing
image layers but compile again; `make deploy` avoids an unnecessary second
rollout.

## Observability

The default profile enables logs, APM, profiling, cluster checks, process
collection, PostgreSQL/Redis/nginx Autodiscovery, browser RUM, and continuous
Puppeteer browser traffic. The frontend builds at container startup, allowing
the RUM values supplied to the Kubernetes Secret to be embedded safely at
runtime.

All images are immutable multi-architecture OCI index digests in
`manifests/base/apps.yaml`. Their source is the current published image set;
the project does not build, copy, or alter Storedog source. Exact provenance is
recorded in `IMAGES.md`.

## MCP setup

```bash
make mcp-config
```

This creates an ignored, eight-hour ServiceAccount token kubeconfig and builds
the sibling MCP source without changing it. Start the output command shown by
the target from this directory. Its configuration enables `core` and `config`,
validates API calls, denies Secrets and RBAC resources, and defaults destructive
operations to denial when the MCP client cannot ask for confirmation.

The MCP identity can inspect common cluster resources and metrics cluster-wide,
but can mutate only selected workload resources in the `dogshop` namespace. It
cannot read Secrets or modify RBAC.

`make mcp-config` can run before `make deploy`; it creates only the Dogshop
namespace and the MCP ServiceAccount/RBAC resources needed to issue the
restricted kubeconfig.

## Demonstration scenarios

Start from a healthy deployment, then apply exactly one fault:

```bash
make fault SCENARIO=service-selector
make fault SCENARIO=invalid-image
make fault SCENARIO=invalid-readiness
make reset
```

Suggested MCP prompts:

- `Why are Dogshop ads unavailable? Diagnose the service endpoints and fix the cause.`
- `Find the workload with an image pull failure in dogshop, explain the Warning events, and repair it.`
- `Why is the frontend rollout not completing? Inspect the probe failure and repair it.`
- `Scale the dogshop ads Deployment to three replicas and verify the rollout.`
- `Show CPU and memory usage for Dogshop pods, then inspect logs from the traffic generator.`
- `Delete one ads pod and verify that the Deployment recovers.`

For `resources_create_or_update`, retrieve the complete object first and retain
fields that are not part of the repair. The MCP server uses Server-Side Apply,
not a partial patch API.

## Lifecycle

```bash
make status
make smoke
make down
make destroy
```

`make down` deletes only the `dogshop` namespace. `make destroy` deletes only
the dedicated Minikube profile. The Datadog Operator and `datadog` namespace
remain after `down`; destroy the profile to remove the complete local demo.
