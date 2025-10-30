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

        # Serve CAS reads directly from disk with auth_request
        locations."~ ^/api/cache/cas/(?<id>[^/?]+)$" = {
          extraConfig = ''
            # Only allow GET/HEAD for this location
            if ($request_method !~ ^(GET|HEAD)$) { return 405; }

            # Ask Phoenix to authorize using the same query string
            auth_request /_auth_cas?$args;

            # Serve file directly from disk
            default_type application/octet-stream;
            try_files /cas/$arg_account_handle/$arg_project_handle/cas/$id =404;

            # Low CPU for opaque blobs
            gzip off;
            access_log off;
            add_header X-Auth-Checked "1" always;
            add_header Cache-Control "public, max-age=31536000, immutable";
          '';
        };

        # (No special fallback: non-GET/HEAD returns 405)

        locations."=/_auth_cas" = {
          extraConfig = ''
            internal;
            proxy_pass_request_body off;
            proxy_set_header Content-Length "";
            proxy_set_header X-Request-ID $request_id;
            proxy_set_header Authorization $http_authorization;
            proxy_method HEAD;
            # Forward the same query string (account_handle, project_handle)
            proxy_pass http://127.0.0.1:4000/auth/cas?$args;
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

        # No internal-cas location needed with direct try_files
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
