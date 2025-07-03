# Helm Chart for GoHighLevel-MCP

This repository provides a **Helm chart** to deploy the [GoHighLevel-MCP server](https://github.com/mastanley13/GoHighLevel-MCP) on Kubernetes.  
**Note:** This project is _not_ the original GoHighLevel-MCP server, but a community-maintained Helm chart for streamlined Kubernetes deployment.

---

## About the Upstream Project

[GoHighLevel-MCP](https://github.com/mastanley13/GoHighLevel-MCP) is a foundational server that connects the GoHighLevel community with AI automation via the Model Context Protocol (MCP).  
It provides access to GoHighLevel API endpoints and is intended for development, experimentation, and integration with AI systems.

**You must obtain a PRIVATE INTEGRATIONS API key and Location ID from your GoHighLevel account to use this server.**  
See the [upstream README](https://github.com/mastanley13/GoHighLevel-MCP) for detailed setup and security notes.

---

## Features of This Helm Chart

- Deploys the GoHighLevel-MCP server to Kubernetes
- Supports external HTTPS (TLS) via Ingress
- Built-in rate limiting (via NGINX Ingress annotations)
- Configurable environment variables and secrets
- Autoscaling and resource management
- Works with images from any Docker registry or local builds

---

## Prerequisites

- Kubernetes cluster (local or cloud)
- Helm CLI
- Docker (if building your own image)
- (Recommended) NGINX Ingress Controller installed for HTTPS and rate limiting

---

## Quick Start

### 1. Clone This Helm Chart

```bash
git clone https://github.com//ghl-mcp-helm-chart.git
cd ghl-mcp-helm-chart
```

### 2. Prepare Your Docker Image

#### **Option A: Using a Repository (Recommended for Production)**

1. **Clone the upstream server:**
```bash
git clone https://github.com/mastanley13/GoHighLevel-MCP.git
cd GoHighLevel-MCP
```

2. **Build and push your Docker image:**
```bash
docker build -t /ghl-mcp-server:latest .
docker push /ghl-mcp-server:latest
```

3. **Edit `custom-values.yaml` in this Helm chart:**
```bash
image:
    repository: /ghl-mcp-server
    tag: latest
```

4. **Continue with deployment instructions below.**

#### **Option B: Without a Repository (Advanced/Development Only)**

- Build the image locally on _every_ Kubernetes node:
```bash
docker build -t ghl-mcp-server:local .
```

- In `custom-values.yaml`, set:
```bash
image:
    repository: /ghl-mcp-server
    tag: local
    pullPolicy: Never
```
- **Note:** This only works if each node has the image in its local cache and is not suitable for most production clusters.

---

### 3. Create Your TLS Secret

Obtain a TLS certificate and key for your domain, then create a Kubernetes secret:
```bash
kubectl create secret tls ghl-mcp-tls-secret 
–cert=path/to/tls.crt 
–key=path/to/tls.key 
–namespace 
```


---

### 4. Configure `custom-values.yaml`

```bash

replicaCount: 2

image:
  repository: your-dockerhub-username/ghl-mcp-server
  tag: latest
  pullPolicy: Always

env:
  GHL_API_KEY: "your_private_integrations_api_key"  # Required
  GHL_LOCATION_ID: "your_location_id"               # Required
  GHL_BASE_URL: "https://services.leadconnectorhq.com"
  NODE_ENV: "production"
  PORT: 8000
  LOG_LEVEL: "info"
  CORS_ORIGINS: "*"

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 5
  targetCPUUtilizationPercentage: 60

service:
  type: LoadBalancer
  port: 80
  targetPort: 8000
  annotations: {}


resources:
  limits:
    cpu: 2000m
    memory: 1Gi
  requests:
    cpu: 500m
    memory: 512Mi

ingress:
  enabled: true
  host: your-ghl-mcp.example.com       # Your domain name
  tlsSecret: ghl-mcp-tls-secret        # Name of the Kubernetes TLS secret containing your cert and key

```


---

### 5. Deploy with Helm

```bash
helm install ghl-mcp-server . -f custom-values.yaml
```


---

## Ingress, HTTPS, and Rate Limiting

This chart configures an NGINX Ingress with:

- **HTTPS termination** (using your provided TLS secret)
- **Automatic HTTP→HTTPS redirect**
- **Rate limiting** (default: 10 requests/sec, 100 requests/min per IP)

You can customize these via `custom-values.yaml` and Ingress annotations.

---

## Environment Variables

| Name              | Required | Description                                    |
|-------------------|----------|------------------------------------------------|
| GHL_API_KEY       | Yes      | Private Integrations API Key (from GHL)        |
| GHL_LOCATION_ID   | Yes      | Your GoHighLevel Location ID                   |
| GHL_BASE_URL      | No       | API base URL (default: services.leadconnectorhq.com) |
| NODE_ENV          | No       | Node environment (default: production)         |
| PORT              | No       | Container port (default: 8000)                 |
| LOG_LEVEL         | No       | Logging verbosity (default: info)              |
| CORS_ORIGINS      | No       | Allowed CORS origins (default: *)              |

---

## Reference

- **Upstream Project:** [mastanley13/GoHighLevel-MCP](https://github.com/mastanley13/GoHighLevel-MCP)
- **This Chart:** Community-maintained Helm deployment for Kubernetes

---

## Security & AI Safety

- **Never expose your API key or credentials.**
- **Always use HTTPS in production.**
- **Monitor and adjust rate limits as needed.**
- **Test thoroughly before production use.**

---

## License

This Helm chart is provided under the license included in the LICENSE file .  
See the upstream [LICENSE](https://github.com/mastanley13/GoHighLevel-MCP/blob/main/LICENSE) for details about GoHighLevel-MCP usage.

---

## Contributing

PRs and suggestions are welcome for improving this Helm chart.  
For core server issues, please contribute to the [upstream project](https://github.com/mastanley13/GoHighLevel-MCP).

---

## Disclaimer

This repository is **not affiliated with or maintained by the original GoHighLevel-MCP authors**.  
It exists solely to provide a Kubernetes deployment option for the community.  
Use at your own risk and always consult the upstream documentation for security and integration guidance.

