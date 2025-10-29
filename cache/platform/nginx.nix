{
  config,
  lib,
  ...
}: {
  services.nginx = {
    enable = true;

    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    virtualHosts = {
      "cache-eu-central-staging.tuist.dev" = lib.mkIf (config.networking.hostName == "cas-cache-eu-central") {
        forceSSL = true;
        enableACME = true;

        locations."/" = {
          proxyPass = "http://localhost:4000";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Port $server_port;

            # Timeouts for large file uploads/downloads
            proxy_connect_timeout 30m;
            proxy_send_timeout 30m;
            proxy_read_timeout 30m;
            send_timeout 30m;

            # Disable buffering for streaming
            proxy_buffering off;
            proxy_request_buffering off;

            # Client body size for large uploads
            client_max_body_size 0;
            client_body_timeout 30m;
          '';
        };

        locations."/internal-cas/" = {
          alias = "/cas/";
          extraConfig = ''
            internal;

            # Disable access log for performance
            access_log off;

            # No caching headers (content-addressable, so safe to cache forever)
            add_header Cache-Control "public, max-age=31536000, immutable";
          '';
        };

        extraConfig = ''
          # Client body size for large uploads
          client_max_body_size 0;
          client_body_timeout 30m;
        '';
      };

      "cache-us-east-staging.tuist.dev" = lib.mkIf (config.networking.hostName == "cas-cache-us-east") {
        forceSSL = true;
        enableACME = true;

        locations."/" = {
          proxyPass = "http://localhost:4000";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Port $server_port;

            # Timeouts for large file uploads/downloads
            proxy_connect_timeout 30m;
            proxy_send_timeout 30m;
            proxy_read_timeout 30m;
            send_timeout 30m;

            # Disable buffering for streaming
            proxy_buffering off;
            proxy_request_buffering off;

            # Client body size for large uploads
            client_max_body_size 0;
            client_body_timeout 30m;
          '';
        };

        locations."/internal-cas/" = {
          alias = "/cas/";
          extraConfig = ''
            internal;

            # Disable access log for performance
            access_log off;

            # No caching headers (content-addressable, so safe to cache forever)
            add_header Cache-Control "public, max-age=31536000, immutable";
          '';
        };

        extraConfig = ''
          # Client body size for large uploads
          client_max_body_size 0;
          client_body_timeout 30m;
        '';
      };
    };
  };

  # ACME certificate configuration
  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "christoph@tuist.dev";
      server = "https://acme-v02.api.letsencrypt.org/directory";
    };
  };

  # Ensure nginx user has access to /cas
  systemd.services.nginx.serviceConfig = {
    ReadOnlyPaths = ["/cas"];
  };
}
