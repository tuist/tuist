{config, ...}: {
  services.nginx = {
    enable = true;

    # Disable NixOS convenience presets — we set every directive
    # explicitly to control the sendfile / kTLS / proxy pipeline.
    recommendedGzipSettings = false;
    recommendedOptimisation = false;
    recommendedProxySettings = false;
    recommendedTlsSettings = false;

    appendConfig = ''
      # One worker per vCPU; each runs its own event loop.
      worker_processes auto;
      # Let workers open enough FDs for connections + open_file_cache +
      # CAS files. Must match or exceed the systemd LimitNOFILE below.
      worker_rlimit_nofile 1048576;
      # Shared thread pool for AIO reads of large CAS files (directio path).
      # 32 threads cover ~16 concurrent large-file downloads with double-
      # buffered output_buffers. Queue depth absorbs download bursts.
      thread_pool cacheio threads=32 max_queue=65536;
    '';

    eventsConfig = ''
      # Max simultaneous connections per worker. With auto workers on an
      # 8-vCPU node this allows 32 K total connections.
      worker_connections 4096;
      # Accept all pending connections at once instead of one per epoll
      # wake — reduces event-loop iterations during connection bursts.
      multi_accept on;
    '';

    appendHttpConfig = ''
      # Multiplex downloads over a single TCP connection per client,
      # avoiding per-request TLS handshakes and connection overhead.
      http2 on;

      # Zero-copy file transfer — the kernel moves data straight from
      # the page cache to the NIC via kTLS, bypassing user-space copies.
      sendfile on;
      # Cork the socket until a full frame is ready (combines headers +
      # body into fewer packets), then uncork immediately with nodelay
      # so the last partial frame isn't held back by Nagle's algorithm.
      tcp_nopush on;
      tcp_nodelay on;

      # Long-lived connections for HTTP/2 clients that download many
      # artifacts in sequence. 50 K requests per connection avoids
      # renegotiation overhead during large CI fetches.
      keepalive_timeout 120s;
      keepalive_requests 50000;

      # Cap concurrent streams so one HTTP/2 connection cannot monopolise
      # a worker. 256 covers the CLI's 100-module concurrency with room
      # for registry and Xcode requests on the same connection.
      http2_max_concurrent_streams 256;
      # 16 KB is the default HTTP/2 max frame size; values above this
      # are silently split by most clients. Matches the spec ceiling.
      http2_chunk_size 16k;

      # Cap each sendfile() call so one large transfer cannot monopolise
      # a worker's event-loop iteration. The worker yields after 512 KB,
      # processes queued events (tiny-file requests), then continues.
      sendfile_max_chunk 512k;

      log_format timed_combined '$remote_addr - $remote_user [$time_local] '
        '"$request" $status $body_bytes_sent '
        '"$http_referer" "$http_user_agent" '
        'rt=$request_time '
        'uct=$upstream_connect_time '
        'uht=$upstream_header_time '
        'urt=$upstream_response_time '
        'upstream_addr=$upstream_addr '
        'status=$status '
        'request_length=$request_length '
        'method=$request_method';

      # Buffer log writes so tiny-file bursts don't trigger a write()
      # syscall per request on the worker's event loop.
      access_log /var/log/nginx/access.log timed_combined buffer=256k flush=5s;

      # Swift Package Registry requires a Content-Version response header.
      # X-Accel-Redirect to proxy_pass locations replaces upstream headers,
      # so we re-inject it only for registry requests.
      map $request_uri $registry_content_version {
        "~^/api/registry/swift/" "1";
        default "";
      }

      upstream cache_upstream {
        server unix:/run/cache/current.sock;
        # Idle upstream connections held open per worker. Sized to
        # absorb 10 K+ req/s bursts so most requests reuse a warm
        # connection instead of opening a new one (which would hit
        # the listen backlog).
        keepalive 256;
        keepalive_timeout 120s;
        keepalive_requests 50000;
      }
    '';

    virtualHosts = {
      # Localhost-only metrics endpoint
      "localhost" = {
        listen = [
          {
            addr = "127.0.0.1";
            port = 80;
            extraParameters = ["default_server"];
          }
          {
            addr = "[::1]";
            port = 80;
            extraParameters = ["default_server"];
          }
        ];

        locations."= /metrics" = {
          proxyPass = "http://cache_upstream";
          extraConfig = ''
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto http;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Port $server_port;
          '';
        };
      };

      # Main HTTPS server
      "${config.networking.hostName}.tuist.dev" = {
        forceSSL = true;
        enableACME = true;
        # Offload TLS record encryption to the kernel. Combined with
        # sendfile this gives true zero-copy: data goes page-cache → NIC
        # without entering user-space. ~15-30 % throughput gain on downloads.
        kTLS = true;

        extraConfig = ''
          # No upload size limit — large cache artifacts can be hundreds of MB.
          client_max_body_size 0;
          # Generous body timeout for slow upload connections.
          client_body_timeout 30m;
        '';

        locations."/metrics" = {
          return = "404";
        };

        locations."/api/cache/" = {
          extraConfig = ''
            default_type application/json;

            if ($http_authorization = "") {
              return 401 '{"message":"Missing Authorization header"}';
            }

            proxy_pass http://cache_upstream;

            # HTTP/1.1 + empty Connection header enables upstream keepalive
            # pooling, avoiding a new unix-socket connect per request.
            proxy_http_version 1.1;
            proxy_set_header Connection "";

            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Port $server_port;

            # Long timeouts for large artifact uploads (up to 300 MB).
            proxy_connect_timeout 30m;
            proxy_send_timeout 30m;
            proxy_read_timeout 30m;
            send_timeout 30m;

            # Stream uploads/downloads through without buffering to disk.
            # Phoenix responds fast (<200 ms); buffering would only add
            # latency and disk I/O contention with CAS reads.
            proxy_buffering off;
            proxy_request_buffering off;
          '';
        };

        locations."/" = {
          proxyPass = "http://cache_upstream";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Port $server_port;

            proxy_connect_timeout 30m;
            proxy_send_timeout 30m;
            proxy_read_timeout 30m;
            send_timeout 30m;

            proxy_buffering off;
            proxy_request_buffering off;
          '';
        };

        locations."/internal/local/" = {
          extraConfig = ''
            internal;
            alias /cas/;
            types { }
            default_type application/octet-stream;
            sendfile on;
            # Binary artifacts — compression wastes CPU and most are
            # already compressed (zips, frameworks).
            gzip off;

            # Files ≥ 8 MB bypass the page cache (O_DIRECT) and are read
            # in the cacheio thread pool so the worker stays non-blocking.
            # Files < 8 MB use sendfile + kTLS (zero-copy, kernel TLS).
            # Keeping the threshold high maximises the zero-copy window;
            # sendfile_max_chunk (512 KB) prevents any single sendfile()
            # call from blocking the event loop for more than ~1 ms on SSD.
            aio threads=cacheio;
            directio 8m;
            directio_alignment 4k;
            # Double-buffer AIO reads: one buffer sends while the next
            # is filled by the thread pool, smoothing large-file throughput.
            output_buffers 2 512k;

            # CAS keys are content-addressed — once written, never changed.
            # Immutable lets clients skip conditional requests entirely.
            add_header Cache-Control "public, max-age=31536000, immutable";
            add_header Content-Version $registry_content_version;

            # CAS artifacts are immutable (content-addressed), so we can
            # cache many more FDs and revalidate less often.
            # max is per-worker — 20 K × N workers stays within FD limits.
            open_file_cache max=20000 inactive=600s;
            open_file_cache_valid 120s;
            open_file_cache_min_uses 1;
            open_file_cache_errors off;
          '';
        };

        locations."~ ^/internal/remote/(.*?)/(.*?)/(.*)" = {
          extraConfig = ''
            internal;
            # The cache download API contract expects application/octet-stream.
            # When proxying a presigned S3 URL, nginx would otherwise forward S3's
            # object metadata (often application/zip), which breaks strict clients.
            proxy_hide_header Content-Type;
            default_type application/octet-stream;
            # Resolve S3 hostnames via Cloudflare; cache DNS for 5 min to
            # avoid a lookup per download. IPv6 off avoids dual-stack delays.
            resolver 1.1.1.1 ipv6=off valid=300s;
            resolver_timeout 5s;
            set $download_url $1://$2/$3;
            # Keepalive to S3: HTTP/1.1 + empty Connection reuses TCP
            # connections across consecutive downloads from the same bucket.
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_set_header Host $2;
            proxy_socket_keepalive on;
            # SNI required — S3 virtual-hosted buckets need the correct
            # hostname in the TLS ClientHello to route to the right bucket.
            proxy_ssl_server_name on;
            proxy_pass $download_url$is_args$args;
            add_header Content-Version $registry_content_version;
            gzip off;
            proxy_request_buffering off;

            # Stream S3 responses directly to the client instead of buffering.
            # With buffering on and no temp-file cap, large artifacts (up to
            # 300 MB) would spill to disk and compete with local CAS reads.
            proxy_buffering off;
            proxy_buffer_size 16k;
            proxy_buffers 4 16k;
            proxy_busy_buffers_size 16k;

            # Intercept S3 error/redirect responses so we can return clean
            # JSON errors or follow redirects with the correct Content-Type.
            proxy_intercept_errors on;
            error_page 301 302 307 = @handle_remote_redirect;
            error_page 403 404 = @handle_remote_not_found;
          '';
        };

        locations."@handle_remote_not_found" = {
          extraConfig = ''
            # Disable MIME type detection. The request URI contains filenames like
            # &name=SwiftCompilerPluginMessageHandling.zip which would otherwise
            # trigger nginx to set Content-Type: application/zip instead of JSON.
            types { }
            default_type application/json;
            return 404 '{"message":"Not found"}';
          '';
        };

        locations."@handle_remote_redirect" = {
          extraConfig = ''
            # S3 presigned URLs may 307-redirect (e.g. region redirects).
            # Follow the redirect server-side so clients see a single hop.
            set $saved_redirect_location $upstream_http_location;
            proxy_hide_header Content-Type;
            default_type application/octet-stream;
            proxy_pass $saved_redirect_location;
            add_header Content-Version $registry_content_version;
          '';
        };
      };
    };
  };

  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "christoph@tuist.dev";
      server = "https://acme-v02.api.letsencrypt.org/directory";
    };
  };

  systemd.services.nginx.serviceConfig = {
    # Prevent nginx from writing to the CAS volume — all writes go
    # through the Phoenix app which manages content-addressing.
    ReadOnlyPaths = ["/cas"];
    # Match worker_rlimit_nofile so the systemd limit doesn't cap it.
    LimitNOFILE = 1048576;
  };
}
