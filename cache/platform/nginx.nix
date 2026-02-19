{config, ...}: {
  services.nginx = {
    enable = true;

    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = false;

    appendConfig = ''
      worker_processes auto;
      worker_rlimit_nofile 1048576;
      thread_pool cacheio threads=32 max_queue=65536;
    '';

    eventsConfig = ''
      worker_connections 4096;
      multi_accept on;
    '';

    appendHttpConfig = ''
      http2 on;
      ssl_session_cache shared:SSL:50m;
      ssl_session_timeout 1h;
      ssl_session_tickets on;
      ssl_prefer_server_ciphers off;
      keepalive_requests 50000;
      http2_max_concurrent_streams 256;
      http2_chunk_size 16k;

      # Cap each sendfile() call so one large transfer cannot monopolise
      # a worker's event-loop iteration. The worker yields after 1 MB,
      # processes queued events (tiny-file requests), then continues.
      sendfile_max_chunk 1m;

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
        keepalive 512;
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
        kTLS = true;

        extraConfig = ''
          client_max_body_size 0;
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

            proxy_http_version 1.1;
            proxy_set_header Connection "";

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
            gzip off;

            # Files ≥ 4 MB bypass the page cache (O_DIRECT) and are read
            # in the cacheio thread pool so the worker stays non-blocking.
            # Files < 4 MB use sendfile + kTLS (zero-copy, kernel TLS).
            # This keeps the page cache hot for Xcode's tiny-file bursts
            # while large module artifacts don't evict them.
            aio threads=cacheio;
            directio 4m;
            # Double-buffer AIO reads: one buffer sends while the next
            # is filled by the thread pool, smoothing large-file throughput.
            output_buffers 2 512k;

            add_header Cache-Control "public, max-age=31536000, immutable";
            add_header Content-Version $registry_content_version;

            # CAS artifacts are immutable (content-addressed), so we can
            # cache many more FDs and revalidate less often.
            open_file_cache max=100000 inactive=600s;
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
            resolver 1.1.1.1 ipv6=off;
            set $download_url $1://$2/$3;
            proxy_set_header Host $2;
            proxy_pass $download_url$is_args$args;
            add_header Content-Version $registry_content_version;
            gzip off;
            proxy_request_buffering off;

            # Stream S3 responses directly to the client instead of buffering.
            # With buffering on and no temp-file cap, large artifacts (up to
            # 300 MB) would spill to disk and compete with local CAS reads.
            proxy_buffering off;
            proxy_buffer_size 16k;

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
    ReadOnlyPaths = ["/cas"];
    LimitNOFILE = 1048576;
  };
}
