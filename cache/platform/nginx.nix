{config, ...}: {
  services.nginx = {
    enable = true;

    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = false;

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
        'cache=$upstream_cache_status';

      access_log /var/log/nginx/access.log timed_combined;
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
          proxyPass = "http://unix:/run/cache/current.sock:/metrics";
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

        locations."/" = {
          proxyPass = "http://unix:/run/cache/current.sock:/";
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
            resolver 1.1.1.1 ipv6=off;
            set $download_url $1://$2/$3;
            proxy_set_header Host $2;
            proxy_pass $download_url$is_args$args;
            proxy_request_buffering off;
            proxy_buffering off;
            proxy_intercept_errors on;
            error_page 301 302 307 = @handle_remote_redirect;
          '';
        };

        locations."@handle_remote_redirect" = {
          extraConfig = ''
            set $saved_redirect_location $upstream_http_location;
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
