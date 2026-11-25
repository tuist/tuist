{{/*
Annotations every Ingress in front of the gateway carries: signed requests
stream through unbuffered, and neither log keeps their presigned queries.
*/}}
{{- define "rustfs.streamingIngressAnnotations" -}}
nginx.ingress.kubernetes.io/proxy-body-size: "0"
# Unbuffered HTTP/2 stream receive windows otherwise stay near 64 KiB.
# Keep streaming; bound the larger receive buffer to this bucket's locations.
nginx.ingress.kubernetes.io/client-body-buffer-size: "1m"
nginx.ingress.kubernetes.io/proxy-request-buffering: "off"
nginx.ingress.kubernetes.io/proxy-buffering: "off"
nginx.ingress.kubernetes.io/proxy-read-timeout: "120"
nginx.ingress.kubernetes.io/proxy-send-timeout: "120"
nginx.ingress.kubernetes.io/proxy-next-upstream: "off"
# The controller's format logs $request, presigned query included. The
# gateway logs these requests without it.
nginx.ingress.kubernetes.io/enable-access-log: "false"
nginx.ingress.kubernetes.io/ssl-redirect: "true"
{{- end }}
