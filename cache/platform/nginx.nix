{
  config,
  ...
}: {
  services.nginx = {
    enable = true;

    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    # Disable to avoid conflicts with custom TLS tuning below
    recommendedTlsSettings = false;

    # Global HTTP/TLS tuning. Focus: fewer TLS handshakes and longer-lived
    # client connections to reduce CPU without relying on open_file_cache.
    appendHttpConfig = ''
      # Reuse TLS sessions aggressively to cut handshake CPU
      ssl_session_cache shared:SSL:50m;
      ssl_session_timeout 1h;
      ssl_session_tickets off;
      ssl_prefer_server_ciphers off;
      ssl_stapling on;
      ssl_stapling_verify on;

      # Keep connections hot; rely on module's keepalive_timeout; set requests only
      keepalive_requests 10000;

      # Increase HTTP/2 concurrency (applies when http2 is negotiated)
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
