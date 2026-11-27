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
# The one buffer an unbuffered response passes through; see the gateway's
# proxy_buffer_size.
nginx.ingress.kubernetes.io/proxy-buffer-size: "64k"
nginx.ingress.kubernetes.io/proxy-read-timeout: "120"
nginx.ingress.kubernetes.io/proxy-send-timeout: "120"
nginx.ingress.kubernetes.io/proxy-next-upstream: "off"
# The controller's format logs $request, presigned query included. The
# gateway logs these requests without it.
nginx.ingress.kubernetes.io/enable-access-log: "false"
nginx.ingress.kubernetes.io/ssl-redirect: "true"
{{- end }}

{{/* The gateway nginx config; the pods carry its checksum. */}}
{{- define "rustfs.gatewayConfig" -}}
default.conf: |
  upstream storage {
    server {{ .Release.Name }}-s3:9000;
    keepalive 32;
  }
  # The ingress appends the client it accepted the connection from as the
  # last X-Forwarded-For entry; earlier entries are whatever the client sent.
  map $http_x_forwarded_for $rustfs_client {
    "~(?:^|,)\s*([0-9A-Fa-f.:]+)\s*$" $1;
    default $remote_addr;
  }
  # Only the access key ID, which is not secret, from SigV4 or SigV2
  # signatures: a presigned URL's credential or the Authorization header.
  # The chart's keys contain hyphens; "=" and "," are excluded so a crafted
  # credential cannot carry a signature into the log.
  map $args $rustfs_query_key_id {
    "~(?:^|&)X-Amz-Credential=([A-Za-z0-9._@+-]{1,128})(?:%2[Ff]|/)" $1;
    "~(?:^|&)AWSAccessKeyId=([A-Za-z0-9._@+-]{1,128})(?:&|$)" $1;
    default "";
  }
  map $http_authorization $rustfs_key_id {
    "~^AWS4-HMAC-SHA256 +Credential=([A-Za-z0-9._@+-]{1,128})/" $1;
    "~^AWS ([A-Za-z0-9._@+-]{1,128}):" $1;
    default $rustfs_query_key_id;
  }
  map $http_authorization $rustfs_auth {
    "~^AWS" header;
    default $rustfs_query_auth;
  }
  map $rustfs_query_key_id $rustfs_query_auth {
    "" none;
    default presigned;
  }
  # One JSON line per request to stdout, which Alloy ships to Pulse. It must
  # never name a variable that carries the query string ($request,
  # $request_uri, $args, $arg_*, $query_string) or a credential header:
  # presigned queries and Authorization hold signatures. $uri is the path.
  log_format rustfs_access escape=json '{"time":"$time_iso8601","client":"$rustfs_client","peer":"$remote_addr","method":"$request_method","path":"$uri","status":"$status","bytes_sent":"$bytes_sent","request_length":"$request_length","request_time":"$request_time","auth":"$rustfs_auth","key_id":"$rustfs_key_id","user_agent":"$http_user_agent"}';
  server {
    listen 8080;
    access_log /dev/stdout rustfs_access;
    # nginx's error log quotes the whole request line, query included.
    error_log /dev/null;
    client_max_body_size 0;
    client_body_timeout 120s;
    location = /ready { access_log off; return 200; }
    # Only the listed buckets. No console, admin, metrics or peer APIs.
    location ~ ^/({{ join "|" .Values.gateway.buckets }})(?:/|$) {
      proxy_http_version 1.1;
      proxy_set_header Host $http_host;
      proxy_set_header Connection "";
      proxy_request_buffering off;
      proxy_buffering off;
      # Unbuffered, nginx relays each response through one buffer of this
      # size; the 4k default costs a read and a write per 4 KiB, which kept
      # a local repro of this hop near 950 MB/s a connection, 3.7 GB/s at 64k.
      proxy_buffer_size 64k;
      # Unused while unbuffered, but nginx refuses a proxy_buffer_size the
      # default 8 4k buffers cannot hold.
      proxy_buffers 4 64k;
      proxy_connect_timeout 5s;
      proxy_read_timeout 120s;
      proxy_send_timeout 120s;
      proxy_next_upstream off;
      # No URI rewrite: preserve the signed path, query and Host.
      proxy_pass http://storage;
    }
    location / { return 404; }
  }
{{- end }}
