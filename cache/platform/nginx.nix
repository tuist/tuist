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
      ssl_session_tickets on;
      ssl_prefer_server_ciphers off;
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

        locations."/api/cache/cas/" = {
          extraConfig = ''
            # Only allow GET/HEAD for this location
            if ($request_method !~ ^(GET|HEAD)$) { return 405; }

            # Ask Phoenix to authorize (no args in URI). Pass account/project via headers below.
            auth_request /_auth_cas;

            # Serve file directly from disk. Rewrite once to make $uri just "/:id".
            default_type application/octet-stream;
            rewrite ^/api/cache/cas/(.*)$ /$1 break;
            try_files /cas/$arg_account_handle/$arg_project_handle/cas$uri =404;

            # Low CPU for opaque blobs
            gzip off;
            access_log off;
            add_header X-Auth-Checked "1" always;
            add_header Cache-Control "public, max-age=31536000, immutable";
          '';
        };

        locations."=/_auth_cas" = {
          extraConfig = ''
            internal;
            proxy_pass_request_body off;
            proxy_set_header Content-Length "";
            proxy_set_header X-Request-ID $request_id;
            proxy_set_header Authorization $http_authorization;
            proxy_set_header X-Account-Handle $arg_account_handle;
            proxy_set_header X-Project-Handle $arg_project_handle;
            proxy_method HEAD;
            proxy_pass http://127.0.0.1:4000/auth/cas;
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
