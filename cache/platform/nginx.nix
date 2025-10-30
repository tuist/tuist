{
  config,
  ...
}: {
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
      # Enable session tickets to maximize TLS resumption (CPU savings)
      ssl_session_tickets on;
      ssl_prefer_server_ciphers off;
      ssl_stapling on;
      ssl_stapling_verify on;
      keepalive_requests 10000;
      http2_max_concurrent_streams 512;
    '';

    virtualHosts = {
      "${config.networking.hostName}.tuist.dev" = {
        forceSSL = true;
        enableACME = true;

        extraConfig = ''
          client_max_body_size 0;
          client_body_timeout 30m;
        '';

        # Intercept GET/HEAD to legacy API route and serve directly from disk
        # after authorizing via auth_request. Other methods (e.g. POST) fall through
        # to Phoenix via the root proxy location.
        locations."~ ^/api/cache/cas/[^/?]+$" = {
          extraConfig = ''
            # Only handle GET/HEAD here; send others to Phoenix
            error_page 405 = @apicas_proxy;
            limit_except GET HEAD { return 405; }

            # Authorize by consulting Phoenix with project context from query args
            auth_request /_auth_cas?account_handle=$arg_account_handle&project_handle=$arg_project_handle;

            # After auth, rewrite to internal-cas path and let nginx serve from disk
            rewrite ^/api/cache/cas/(.*)$ /internal-cas/$arg_account_handle/$arg_project_handle/cas/$1 last;

            access_log off;
            gzip off;
          '';
        };

        # Fallback named location to proxy to Phoenix for non-GET/HEAD
        locations."@apicas_proxy" = {
          proxyPass = "http://127.0.0.1:4000";
          proxyWebsockets = false;
          extraConfig = ''
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Port $server_port;
          '';
        };

        locations."=/_auth_cas" = {
          extraConfig = ''
            internal;
            proxy_pass_request_body off;
            proxy_set_header Content-Length "";
            proxy_set_header X-Request-ID $request_id;
            proxy_set_header Authorization $http_authorization;
            proxy_method HEAD;
            proxy_pass http://127.0.0.1:4000/auth/cas$is_args$args;
          '';
        };

        locations."/" = {
          proxyPass = "http://127.0.0.1:4000";
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

        locations."/internal-cas/" = {
          alias = "/cas/";
          extraConfig = ''
            internal;
            access_log off;
            default_type application/octet-stream;
            # Disable compression for opaque CAS blobs to save CPU
            gzip off;
            add_header Cache-Control "public, max-age=31536000, immutable";
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
