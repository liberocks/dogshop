---
marp: true
theme: default
paginate: true
size: 16:9
style: |
  section {
    background: #ffffff;
    color: #10243e;
    font-family: Inter, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    font-size: 28px;
    padding: 56px 72px;
  }
  h1, h2, h3 { color: #0b5cab; }
  h1 { font-size: 1.5em; }
  h2 { font-size: 1.35em; }
  strong { color: #0b5cab; }
  code { background: #e8eff8; color: #10243e; }
  pre { font-size: 0.58em; }
  section.lead {
    background: #0b1f3a;
    color: #f7f9fc;
    text-align: left;
  }
  section.lead h1, section.lead h2, section.lead strong { color: #7ed6ff; }
  section.closing {
    background: #0b5cab;
    color: #ffffff;
  }
  section.closing h1, section.closing h2, section.closing strong { color: #ffffff; }
---

<!-- Render with: npx @marp-team/marp-cli PRESENTATION.md --allow-local-files -->

<!-- _class: lead -->
<!-- _paginate: false -->

# From observability to explainability with Datadog & Kubernetes MCP

---

# Observability shows what happened

- **Logs** record events
- **Traces** follow a request
- **Monitoring** shows health and trends

![w:800](presentation-assets/observability.png)

---

# Signals are not yet answers
- Human needs to connect the dot

![w:700](presentation-assets/signals.png)

---

# LLMs add explainability

- Ask in plain language
- Collect relevant evidence
- Explain likely cause and next step

![w:900](presentation-assets/explainability.png)

---

# The Storedog demo

**Goal:** understand a running system and find faults sooner.

![w:700](presentation-assets/demo-overview.png)

---

# Demo 1: get the baseline

> Show CPU and memory usage for Dogshop pods as a Markdown table. Add a simple comparison chart, highlight the three busiest pods, then inspect recent traffic-generator logs for errors. Do not make changes.

---

# Demo 2: ads are unavailable

Run this first `make fault SCENARIO=service-selector` and then send the prompt

**Prompt**

> Why are Dogshop ads unavailable? Correlate the service, endpoints, pods, events, and Datadog signals. Show the evidence in a table, fix the cause, and verify recovery.


---

# Demo 3: one cross-system summary

**Prompt**

> Use Kubernetes MCP to summarize Dogshop workload health and Datadog MCP to find relevant monitors or telemetry. Return one incident-summary table with evidence, impact, and recommended action. Perform read-only operations only.

---

# Other useful questions

- "Which workload has an image pull failure? Explain the warning events and repair it."
- "Why is the frontend rollout not completing? Inspect the failed readiness probe."
- "Scale ads to three replicas and verify the rollout."
- "Delete one ads pod and verify that the Deployment recovers."

---

# Closing remarks

- Observability gives us evidence
- MCP gives an LLM controlled access to that evidence
- Explainability helps teams understand and respond sooner
