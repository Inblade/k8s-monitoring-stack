# k8s-monitoring-stack

[![ci](https://github.com/Inblade/k8s-monitoring-stack/actions/workflows/ci.yml/badge.svg)](https://github.com/Inblade/k8s-monitoring-stack/actions/workflows/ci.yml)
[![Prometheus](https://img.shields.io/badge/prometheus-3.x-E6522C?logo=prometheus&logoColor=white)](https://prometheus.io)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

Production-grade Kubernetes monitoring platform blueprint: [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) deployed to GKE via ArgoCD, with SLO burn-rate alerting and multi-channel routing (Slack + PagerDuty).

This is a **reference implementation** distilled from several years of running Prometheus-based monitoring in production on GKE and bare-metal clusters. It is a template, not a copy of any company's internal repository — adapt values, thresholds, and routing to your environment.

## Why

Most "getting started" monitoring guides stop at `helm install`. In production you also need:

- **GitOps delivery** — the stack itself is deployed and drift-corrected by ArgoCD, ordered with sync waves (CRDs before workloads).
- **Bounded resource usage** — explicit retention, `retentionSize`, and resource requests/limits so Prometheus does not evict its neighbours.
- **Actionable alerting** — multi-window burn-rate SLO alerts (Google SRE Workbook style) instead of noisy static thresholds; pages go to PagerDuty, tickets go to Slack.
- **HA where it matters** — 2 Alertmanager replicas, persistent storage on SSD, pod anti-affinity assumptions baked into the values.

## Structure

```
.
├── argocd/
│   └── application.yaml      # ArgoCD Application (kube-prometheus-stack, sync waves, ServerSideApply)
├── helm/
│   └── values-prod.yaml      # Production values: retention, resources, Alertmanager routing
├── alerts/
│   ├── node-alerts.yaml      # PrometheusRule: node capacity, disk, memory, kubelet health
│   └── slo-alerts.yaml       # PrometheusRule: multi-window multi-burn-rate SLO alerts
├── dashboards/
│   └── README.md             # How dashboards are provisioned (sidecar + ConfigMaps)
├── tests/
│   ├── node-alerts.test.yaml # promtool unit tests: thresholds and label joins
│   └── slo-alerts.test.yaml  # promtool unit tests: burn rates fire and stay quiet
├── scripts/
│   └── render-rules.py       # Unwraps PrometheusRule CRDs into plain rule files
├── Makefile
├── LICENSE
└── .gitignore
```

## Usage

1. Create the secrets referenced by Alertmanager (webhook URL and routing key are mounted from Secrets, never committed):

   ```bash
   kubectl -n monitoring create secret generic alertmanager-slack \
     --from-file=webhook-url=./slack-webhook-url
   kubectl -n monitoring create secret generic alertmanager-pagerduty \
     --from-file=routing-key=./pagerduty-routing-key
   ```

2. Point the Application at your fork and apply it:

   ```bash
   kubectl apply -n argocd -f argocd/application.yaml
   ```

3. Apply the alert rules (or let ArgoCD manage them from a second Application):

   ```bash
   kubectl apply -n monitoring -f alerts/
   ```

4. Validate rules before merging:

   ```bash
   promtool check rules <(yq '.spec' alerts/slo-alerts.yaml)
   ```

## Testing the alerts

Alerting rules are code, and untested rules are the kind of code that is wrong
for six months and then wrong at 03:00. Everything here runs locally in
seconds, with no cluster:

```bash
make check     # render + promtool check + unit tests + yamllint
make test      # just the alert unit tests
```

`promtool check rules` only proves the PromQL parses. The unit tests in
`tests/` assert behaviour:

- **Burn rates fire on the failure they were designed for.** A sustained 2%
  error rate trips the 14.4x fast burn within the hour; a 0.05% rate — half
  the allowed budget — trips nothing at all.
- **Silence is asserted as carefully as firing.** A healthy service and a
  service with no traffic at all both produce zero alerts. The no-traffic case
  matters: the error ratio is `0/0`, and a careless rewrite of that expression
  is exactly how phantom pages appear on a quiet weekend.
- **Thresholds match their summaries.** Every alert whose annotation claims a
  number is checked against that number, so the two cannot drift apart.
- **Label joins actually produce a result.** `KubeletTooManyPods` joins two
  metrics from different exporters `on (node)`. If either side loses that
  label the match yields nothing and the alert silently stops existing — a
  failure mode that looks identical to "everything is fine". The test pins the
  assumption down.
- **Clock skew only pages when it is not converging.** A node whose offset is
  large but shrinking is already being fixed by ntp; the `deriv` half of that
  expression exists to keep it quiet, and the test proves it does.

CI additionally validates every manifest against its schema with kubeconform,
including the `PrometheusRule` and Argo CD `Application` CRDs.

Because the manifests are custom resources rather than plain rule files,
`scripts/render-rules.py` unwraps `spec.groups` into `.rendered/` first. It
also rejects a manifest that is not a `PrometheusRule`, or a rule group with
no name or no rules.

## Design notes

- **Sync wave ordering**: CRDs land in wave `0` (ServerSideApply avoids the 262KB annotation limit on large CRDs), the chart itself in wave `1`, custom PrometheusRules in wave `2`.
- **Retention**: 30 days / 45GB cap on a 50Gi SSD PVC. Long-term storage belongs in Thanos or Mimir, not in local TSDB.
- **SLO alerting**: fast-burn (14.4x over 1h/5m) pages immediately; slow-burn (3x over 6h/30m and 1x over 3d/6h) creates tickets. See `alerts/slo-alerts.yaml`.

## License

MIT — see [LICENSE](LICENSE).
