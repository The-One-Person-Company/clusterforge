microk8s enable prometheus
microk8s enable grafana

microk8s kubectl get secret -n monitoring monitoring-grafana -o jsonpath="{.data.admin-password}" | base64 -d

chmod +x memory-monitor.sh
crontab -l | { cat; echo "*/5 * * * * /path/to/memory-monitor.sh"; } | crontab -

