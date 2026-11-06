# Only the published 1.39.0 overlay is MCP-only. Later releases must retain
# all exact ingestion routes and permit Pulse's 4 MiB receiver body limit.
(if $version == "1.39.0" then ["/mcp"]
 else ["/mcp", "/api/v1/write", "/loki/api/v1/push", "/v1/traces"] end) as $paths |
([.[] | select(.kind == "Deployment")] | length == 1) and
([.[] | select(.kind == "Deployment")][0] |
  .metadata.name == "pulse" and .spec.replicas == 1 and .spec.strategy.type == "Recreate" and
  ([.spec.template.spec.containers[].image] == [$image]) and
  ([.spec.template.spec.containers[].env[]?.valueFrom.secretKeyRef.name // empty] | unique == ["pulse-credentials"])) and
([.[] | select(.kind == "ExternalSecret" and .metadata.name == "pulse-credentials")] | length == 1) and
([.[] | select(.kind == "Service" and .metadata.name == "pulse")][0] |
  .spec.type == "ClusterIP" and ((.spec.externalIPs // []) | length == 0)) and
([.[] | select(.kind == "Ingress")] | length == 1) and
([.[] | select(.kind == "Ingress")][0] |
  .metadata.name == "pulse" and .spec.ingressClassName == "nginx" and
  ($version == "1.39.0" or .metadata.annotations["nginx.ingress.kubernetes.io/proxy-body-size"] == "4m") and
  .spec.rules == [{host: $host, http: {paths:
    ($paths | map({path: ., pathType: "Exact",
      backend: {service: {name: "pulse", port: {name: "http"}}}}))}}] and
  .spec.tls == [{hosts: [$host], secretName: "pulse-tls"}]) and
all(.[]; .kind != "Secret" and .kind != "HorizontalPodAutoscaler")
