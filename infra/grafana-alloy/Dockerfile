FROM grafana/alloy:v1.11.0

COPY config.alloy /etc/alloy/config.alloy

# We are overriding `http.listen-addr` to bind to all interfaces since Render requires even private services to have an HTTP endpoint for health checks.
# This is not exposed to the internet since Alloy is defined as `pserv.`
CMD ["run", "/etc/alloy/config.alloy", "--storage.path=/var/lib/alloy/data", "--server.http.listen-addr=0.0.0.0:12345"]
