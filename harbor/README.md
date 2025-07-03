# Harbor Private Registry
    ██╗  ██╗ █████╗ ██████╗ ██████╗  ██████╗ ██████╗ 
    ██║  ██║██╔══██╗██╔══██╗██╔══██╗██╔═══██╗██╔══██╗
    ███████║███████║██████╔╝██████╔╝██║   ██║██████╔╝
    ██╔══██║██╔══██║██╔══██╗██╔══██╗██║   ██║██╔══██╗
    ██║  ██║██║  ██║██║  ██║██████╔╝╚██████╔╝██║  ██║
    ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝  ╚═════╝ ╚═╝  ╚═╝         
         Private Registry Installer (Helm)

         
This directory contains the configuration for deploying Harbor as a private container registry in your TOPC automation server.

## Overview

Harbor is an open-source registry that secures artifacts with policies and role-based access control, ensures images are scanned and free from vulnerabilities, and signs images as trusted. It's a CNCF Graduated project that delivers compliance, performance, and interoperability.

## Features

- **Private Container Registry**: Store and manage your Docker images privately
- **Vulnerability Scanning**: Built-in security scanning for container images
- **Role-Based Access Control**: Fine-grained permissions and user management
- **Image Signing**: Trust and verify your container images
- **Multi-tenant**: Support for multiple projects and repositories
- **Web UI**: User-friendly interface for managing images and projects

## Architecture

This deployment uses:
- **Single Instance**: Designed for single-node Kubernetes clusters
- **Internal Database**: Uses the existing PostgreSQL instance from the database stack
- **Internal Redis**: Uses the existing Redis instance for caching
- **Persistent Storage**: PVC for registry data and configuration
- **TLS Termination**: Automatic SSL certificate management via cert-manager

## Components

- **Harbor Core**: Main registry service
- **Harbor Portal**: Web UI for management
- **Harbor Registry**: Docker registry backend
- **Harbor Database**: Uses existing PostgreSQL
- **Harbor Redis**: Uses existing Redis for caching
- **Harbor Job Service**: Background job processing
- **Harbor Log**: Log collection service

## Configuration

### Environment Variables

Add these variables to your `.env` file:

```env
# Harbor Configuration
HARBOR_SUBDOMAIN="harbor"
HARBOR_STORAGE_SIZE=50Gi
HARBOR_STORAGE_CLASS=fast
HARBOR_ADMIN_PASSWORD=change_this_password
HARBOR_SECRET_KEY=your_secret_key_here_min_32_chars
HARBOR_DATABASE_HOST=postgres
HARBOR_DATABASE_PORT=5432
HARBOR_DATABASE_NAME=harbor
HARBOR_DATABASE_USER=harbor
HARBOR_DATABASE_PASSWORD=change_this_password
HARBOR_REDIS_HOST=redis
HARBOR_REDIS_PORT=6379
HARBOR_REDIS_PASSWORD=
HARBOR_VERSION=v2.13.1
HARBOR_ADMIN="username"
HARBOR_GIT_TOKEN=""
HARBOR_REGISTRY_SUBDOMAIN="registry"
```

### Required Database Setup

The Harbor installation script will automatically create the required database and user in PostgreSQL using a Kubernetes Job. This approach ensures:

- **Idempotent Operations**: Safe to run multiple times
- **Proper Permissions**: Full database access for Harbor
- **Error Handling**: Clear feedback if database setup fails
- **Kubernetes Native**: Uses Kubernetes Jobs for database initialization

The initialization job will:
1. Connect to the existing PostgreSQL instance
2. Create the Harbor database (`${HARBOR_DATABASE_NAME}`)
3. Create the Harbor user (`${HARBOR_DATABASE_USER}`)
4. Grant all necessary permissions
5. Set up default privileges for future objects

**Note**: The job uses the root PostgreSQL credentials (`POSTGRES_USER` and `POSTGRES_PASSWORD`) to create the Harbor-specific database and user.

## Installation

1. **Prepare Environment**: Add the required variables to your `.env` file
2. **Install Database**: Ensure PostgreSQL and Redis are running
3. **Run Installer**: Execute the Harbor installation script
4. **Access Harbor**: Navigate to `https://harbor.yourdomain.com`

## Usage

### Accessing Harbor

- **Web UI**: `https://harbor.yourdomain.com`
- **Registry**: `registry.yourdomain.com`
- **Default Admin**: `admin` / `your_admin_password`

### Docker Login

```bash
# Login to your private registry
docker login harbor.yourdomain.com

# Push an image
docker tag myapp:latest harbor.yourdomain.com/myproject/myapp:latest
docker push harbor.yourdomain.com/myproject/myapp:latest

# Pull an image
docker pull harbor.yourdomain.com/myproject/myapp:latest
```

### Creating Projects

1. Log into the Harbor web UI
2. Navigate to "Projects" → "New Project"
3. Set project name and visibility
4. Configure vulnerability scanning settings

### User Management

- **Admin**: Full system access
- **Project Admin**: Manage specific projects
- **Developer**: Push/pull images
- **Guest**: Pull public images only

## Security Features

- **TLS Encryption**: All traffic encrypted with automatic certificate management
- **Vulnerability Scanning**: Built-in Clair integration for CVE scanning
- **Image Signing**: Content trust and verification
- **Access Control**: Role-based permissions
- **Audit Logging**: Complete activity tracking

## Monitoring

Harbor provides:
- **Health Checks**: Built-in readiness and liveness probes
- **Metrics**: Prometheus-compatible metrics endpoint
- **Logs**: Structured logging for all components
- **Dashboard**: Web-based monitoring interface

## Troubleshooting

### Common Issues

1. **Database Connection**: Ensure PostgreSQL is running and accessible
2. **Storage Issues**: Check PVC status and storage class
3. **TLS Certificates**: Verify cert-manager is working correctly
4. **Redis Connection**: Ensure Redis is available for caching

### Logs

```bash
# Check Harbor logs
kubectl logs -n harbor deployment/harbor-core
kubectl logs -n harbor deployment/harbor-portal
kubectl logs -n harbor deployment/harbor-registry

# Check PostgreSQL initialization job logs
kubectl logs -n harbor job/harbor-postgres-init
```

### Health Checks

```bash
# Check Harbor health
kubectl get pods -n harbor
kubectl describe pod -n harbor <pod-name>

# Check PostgreSQL initialization job status
kubectl get jobs -n harbor
kubectl describe job harbor-postgres-init -n harbor
```

## Backup and Recovery

Harbor data is stored in:
- **Database**: PostgreSQL (backed up with Velero)
- **Registry Storage**: PVC (backed up with Velero)
- **Configuration**: ConfigMaps and Secrets

## Database Recovery & Maintenance

### Clean (Delete) Harbor Database
If you want to completely reset Harbor (for example, after a failed migration or to start fresh), you can use the menu option:

- **❌ Delete Harbor database and user (DANGEROUS)**
  - This will drop the Harbor database and user from PostgreSQL. **All Harbor data will be lost.**
  - After running this, re-run the install to re-create the database and user.

### Clear Dirty Migration Flag
If you see an error like `Dirty database version ... Fix and force version` in Harbor logs, use the menu option:

- **🛠️  Force clear dirty migration flag**
  - This will connect to the Harbor database and clear the 'dirty' flag in the migration table.
  - Use this only if you see a migration error and want to force Harbor to continue.
  - After running this, restart the Harbor pods.

You can access both options from the interactive install script menu. They are safe to use for recovery, but the database delete is destructive and should only be used if you are sure you want to lose all Harbor data. 

## Resources

- [Harbor Documentation](https://goharbor.io/docs/)
- [Harbor GitHub](https://github.com/goharbor/harbor)
- [CNCF Harbor Project](https://www.cncf.io/projects/harbor/)

## License

Harbor is licensed under the Apache License 2.0. See the [Harbor repository](https://github.com/goharbor/harbor) for full license details. 