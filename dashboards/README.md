# Grafana dashboard provisioning

Dashboards are provisioned declaratively — no manual editing in the Grafana UI, no Grafana persistence.

## How it works

`helm/values-prod.yaml` enables the Grafana sidecar (`grafana.sidecar.dashboards.enabled: true`). The sidecar watches **all namespaces** for ConfigMaps labeled `grafana_dashboard: "1"` and hot-loads their JSON into Grafana. Folder placement is controlled by the `grafana_folder` annotation.

Example wrapper:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: dashboard-slo-overview
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
  annotations:
    grafana_folder: SLO
data:
  slo-overview.json: |
    { "title": "SLO Overview", "uid": "slo-overview", "panels": [] }
```

## Conventions

- One dashboard per ConfigMap; the `uid` field is mandatory and stable, so links and alert annotations never break.
- Dashboard JSON is exported with "Export for sharing externally" disabled (keeps datasource variables as `${DS_PROMETHEUS}`-free direct references handled by provisioning).
- Teams ship dashboards in their own namespaces next to their apps; the sidecar picks them up cluster-wide.
- Review dashboards like code: PRs into this repo, ArgoCD syncs them, drift is corrected automatically.
