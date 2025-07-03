# RustDesk Self-Hosted Server

This directory contains the Kubernetes manifests and installation script to deploy a self-hosted [RustDesk](https://rustdesk.com/) server.

RustDesk is an open-source remote desktop software, offering an alternative to services like TeamViewer and AnyDesk. By self-hosting the server components, you gain full control over your data and infrastructure.

## Deployment Architecture

This deployment consists of two main services and a shared persistent volume:

-   **`hbbs` (RustDesk ID/Rendezvous Server)**: This is the signaling server that helps clients find each other. It handles ID registration and NAT traversal assistance.
-   **`hbbr` (RustDesk Relay Server)**: This service relays traffic between clients when a direct P2P connection cannot be established.
-   **Persistent Volume**: A single `PersistentVolumeClaim` is used to store the server's public/private key pair, ensuring that clients can reconnect after the server restarts.

The web UI is exposed via an Ingress with automated TLS, while the client services are exposed via `LoadBalancer` services.

## Post-Installation: Client Configuration

After the installation script completes, you must configure your RustDesk clients to connect to your new server.

### 1. Retrieve the Public Key

The server automatically generates a cryptographic key pair on its first run. You need to copy the **public key** to your clients.

Execute the following command to retrieve the key:

```bash
microk8s kubectl exec -n rustdesk deployment/rustdesk-hbbs -- cat /root/id_ed25519.pub
```

Copy the output string. It should look something like `aBcDeFgHiJkLmNoPqRsTuVwXyZ1234567890=`.

### 2. Configure the Client

1.  Open your RustDesk client.
2.  Click the menu button (three dots) next to your ID.
3.  Select "ID/Relay Server".
4.  In the **ID Server** field, enter the external IP address of the `hbbs` LoadBalancer service. You can get this from the access information displayed at the end of the installation.
5.  In the **Relay Server** field, you can typically leave this blank, as the `hbbs` server will inform the client about the relay server automatically.
6.  In the **Key** field, paste the public key you retrieved in the previous step.
7.  Click **OK**.

Your client is now configured to use your self-hosted server.

## Environment Variables

The following environment variables are used to configure the RustDesk installation:

| Variable                     | Description                                            | Default      |
| ---------------------------- | ------------------------------------------------------ | ------------ |
| `RUSTDESK_SUBDOMAIN`         | The subdomain for the RustDesk web UI.                 | `rustdesk`   |
| `RUSTDESK_STORAGE_SIZE`      | The size of the persistent volume for key storage.     | `1Gi`        |
| `RUSTDESK_STORAGE_CLASS`     | The storage class for the PVC.                         | `microk8s-hostpath-immediate` |
| `RUSTDESK_ALWAYS_USE_RELAY`  | Force clients to always use the relay server (`Y`/`N`). | `Y`          |
