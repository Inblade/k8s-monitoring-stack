# k8s-monitoring-stack

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

## Design notes

- **Sync wave ordering**: CRDs land in wave `0` (ServerSideApply avoids the 262KB annotation limit on large CRDs), the chart itself in wave `1`, custom PrometheusRules in wave `2`.
- **Retention**: 30 days / 45GB cap on a 50Gi SSD PVC. Long-term storage belongs in Thanos or Mimir, not in local TSDB.
- **SLO alerting**: fast-burn (14.4x over 1h/5m) pages immediately; slow-burn (3x over 6h/30m and 1x over 3d/6h) creates tickets. See `alerts/slo-alerts.yaml`.

## License

MIT — see [LICENSE](LICENSE).
