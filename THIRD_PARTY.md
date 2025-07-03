# Clusterforge — Third-Party Notices & License Attribution  
_Last updated: 23 Jun 2025_

Clusterforge orchestrates a collection of **external open-source projects** that
are retrieved as container images or packages at install time.  
We do **not** redistribute or host their source code or binaries in this
repository.  The table below identifies each project, its primary license, and
an upstream reference so you can review the full license text directly from the
original source.

| Area | Component / Image | Upstream Project / Org | Primary License | Project URL |
|------|-------------------|------------------------|-----------------|-------------|
| **Core Orchestration** | microk8s | Canonical Ltd. | Apache-2.0 | <https://github.com/canonical/microk8s> |
| | MetalLB | metallb.dev | Apache-2.0 | <https://github.com/metallb/metallb> |
| | Minikube base images | Kubernetes SIGs | Apache-2.0 | <https://github.com/kubernetes/minikube> |
| **Networking / Edge** | cloudflared | Cloudflare Inc. | Apache-2.0 | <https://github.com/cloudflare/cloudflared> |
| **Object Storage** | MinIO | MinIO Inc. | AGPL-3.0 | <https://github.com/minio/minio> |
| **Data Layer** | PostgreSQL | PGDG | PostgreSQL License | <https://www.postgresql.org/> |
| | Redis | Redis Ltd. | BSD-3-Clause | <https://github.com/redis/redis> |
| **Data Integration** | Airbyte | Airbyte Inc. | MIT / ELv2* | <https://github.com/airbytehq/airbyte> |
| | NoCodeAPI | NoCodeAPI | MIT | <https://github.com/nocodeapi/server> |
| **Identity & Security** | ZITADEL | CAOS AG | Apache-2.0 | <https://github.com/zitadel/zitadel> |
| | Fail2ban | Cyril Jaquier | GPL-2.0 | <https://github.com/fail2ban/fail2ban> |
| | UFW | Canonical Ltd. | GPL-3.0 | <https://git.launchpad.net/ufw> |
| | AppArmor profiles | Canonical / SUSE | GPL-2.0-with-exceptions | <https://gitlab.com/apparmor/apparmor> |
| **Automation & Workflow** | n8n (Community ED) | n8n GmbH | Sustainable Use License v0 + Apache-2.0 | <https://github.com/n8n-io/n8n> |
| | ntfy | binwiederhier | Apache-2.0 | <https://github.com/binwiederhier/ntfy> |
| | Velero | VMware / Veeam | Apache-2.0 | <https://github.com/vmware-tanzu/velero> |
| **Observability** | Prometheus | The Prometheus Authors | Apache-2.0 | <https://github.com/prometheus/prometheus> |
| | Grafana OSS | Grafana Labs | AGPL-3.0 | <https://github.com/grafana/grafana> |
| | Loki | Grafana Labs | AGPL-3.0 | <https://github.com/grafana/loki> |
| **Misc. Utilities** | jq / curl / bash | Various | MIT / ISC / Expat | see individual projects |

\* Some Airbyte connectors are licensed under Elastic License v2 (ELv2).

---

## Compliance Guidance

* Each listed project retains its original copyright and license; Clusterforge
  does **not** attempt to re-license or modify those terms.  
* If you package Clusterforge together with **copies of these third-party
  binaries or source**, ensure you also comply with any notice, attribution, or
  source-distribution requirements that apply under the relevant licenses.  
* If you believe a dependency or license entry is missing or inaccurate,
  please open an issue or pull request within 30 days of discovery.

---

_This file provides attribution only and does **not** include the full text of
third-party licenses because their code is not hosted in this repository.  Refer
to the project URLs above for complete license details._