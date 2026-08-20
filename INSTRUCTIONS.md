# Codex MCP Setup

This repository has no application-specific runtime. These instructions configure Datadog and Kubernetes MCP servers for Codex.

## Prerequisites

Verify that Codex, `npx`, and Kubernetes access are available:

```sh
codex --version
npx --version
kubectl config current-context
kubectl cluster-info
```

Use a dedicated Kubernetes kubeconfig with read-only permissions where possible.

## Datadog MCP

1. In the Datadog MCP setup page, select the Datadog site and copy its MCP endpoint.
2. Add this entry to `~/.codex/config.toml`:

   ```toml
   [mcp_servers.datadog]
   url = "<YOUR_DATADOG_MCP_ENDPOINT>"
   http_headers = { "X-Datadog-MCP-Toolsets" = "core" }
   ```

   `core` limits the server to its default tools. Do not use `all` unless those tools are required.

3. Authenticate through OAuth:

   ```sh
   codex mcp login datadog
   ```

4. Confirm the registration:

   ```sh
   codex mcp get datadog --json
   ```

5. Start Codex and issue a safe test prompt:

   ```text
   List my Datadog monitors. Do not create, modify, or delete anything.
   ```

The Datadog role requires `mcp_read` and the regular read permission for the requested resource.

## Kubernetes MCP

1. Verify the kubeconfig can access the intended cluster:

   ```sh
   kubectl --kubeconfig "$HOME/.kube/config" get namespaces
   ```

2. Register the server in read-only mode:

   ```sh
   codex mcp add kubernetes -- npx -y kubernetes-mcp-server@latest --read-only --kubeconfig "$HOME/.kube/config"
   ```

   Pin a specific package version instead of `@latest` for a stable production setup.

3. Confirm the registration and package startup:

   ```sh
   codex mcp get kubernetes --json
   npx -y kubernetes-mcp-server@latest --help
   ```

4. Start Codex and issue a safe test prompt:

   ```text
   Using the Kubernetes MCP server, list all namespaces in the configured cluster. Do not make changes.
   ```

## Test Both Servers

1. Start Codex:

   ```sh
   codex
   ```

2. Run this prompt:

   ```text
   Use the Kubernetes MCP server to list namespaces, then use the Datadog MCP server to list monitors. Perform read-only operations only.
   ```

3. If a server is unavailable, inspect the configured servers:

   ```sh
   codex mcp list
   ```
