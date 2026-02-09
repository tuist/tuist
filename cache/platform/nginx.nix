{config, ...}: {
  services.nginx = {
    enable = true;

    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = false;

    appendConfig = ''
      worker_processes auto;
    '';

    eventsConfig = ''
      worker_connections 4096;
    '';

    appendHttpConfig = ''
      http2 on;
      ssl_session_cache shared:SSL:50m;
      ssl_session_timeout 1h;
      ssl_session_tickets on;
      ssl_prefer_server_ciphers off;
      keepalive_requests 10000;
      http2_max_concurrent_streams 512;

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

      access_log /var/log/nginx/access.log timed_combined;

      upstream cache_upstream {
        server unix:/run/cache/current.sock;
        keepalive 128;
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
            default_type application/octet-stream;
            gzip off;
            add_header Cache-Control "public, max-age=31536000, immutable";
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
            proxy_request_buffering off;
            proxy_buffering off;
            proxy_intercept_errors on;
            error_page 301 302 307 = @handle_remote_redirect;
            error_page 403 404 = @handle_remote_not_found;
          '';
        };

        locations."@handle_remote_not_found" = {
          extraConfig = ''
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
  };
}
