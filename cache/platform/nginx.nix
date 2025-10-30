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

        locations."~ ^/api/cache/cas/(.+)$" = {
          root = "/";
          extraConfig = ''
            # Non-GET/HEAD goes to Phoenix via error_page
            error_page 405 = @phoenix_cas;
            if ($request_method !~ ^(GET|HEAD)$) { return 405; }

            # Capture query params before auth_request
            set $account $arg_account_handle;
            set $project $arg_project_handle;

            # GET/HEAD: auth then serve from disk
            auth_request /_auth_cas;

            default_type application/octet-stream;
            rewrite ^/api/cache/cas/(.*)$ /$1 break;
            try_files /cas/$account/$project/cas$uri =404;

            gzip off;
            error_log /var/log/nginx/cas_debug.log debug;
            add_header X-Auth-Checked "1" always;
            add_header X-Account "$account" always;
            add_header X-Project "$project" always;
            add_header Cache-Control "public, max-age=31536000, immutable";
          '';
        };

        locations."@phoenix_cas" = {
          proxyPass = "http://127.0.0.1:4000";
          proxyWebsockets = false;
          extraConfig = ''
            proxy_buffering off;
            proxy_request_buffering off;
          '';
        };

        locations."=/_auth_cas" = {
          extraConfig = ''
            internal;
            proxy_pass_request_body off;
            proxy_set_header Content-Length "";
            proxy_set_header X-Request-ID $request_id;
            proxy_set_header Authorization $http_authorization;
            proxy_method GET;
            proxy_pass http://127.0.0.1:4000/auth/cas?account_handle=$account&project_handle=$project;
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
