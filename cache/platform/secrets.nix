{config, ...}: {
  services.onepassword-secrets = {
    enable = true;
    tokenFile = "/etc/opnix-token";

    secrets = {
      grafanaCloudPromRemoteWriteUrl = {
        reference = "op://cache/Grafana-Alloy/GRAFANA_CLOUD_PROM_REMOTE_WRITE_URL";
        path = "/run/secrets/grafana-cloud-prom-remote-write-url";
        mode = "0400";
        owner = config.systemd.services.grafana-alloy.serviceConfig.User or "root";
        group = config.systemd.services.grafana-alloy.serviceConfig.Group or "root";
        services = ["grafana-alloy"];
      };

      grafanaCloudPromUsername = {
        reference = "op://cache/Grafana-Alloy/GRAFANA_CLOUD_PROM_USERNAME";
        path = "/run/secrets/grafana-cloud-prom-username";
        mode = "0400";
        owner = config.systemd.services.grafana-alloy.serviceConfig.User or "root";
        group = config.systemd.services.grafana-alloy.serviceConfig.Group or "root";
        services = ["grafana-alloy"];
      };

      grafanaCloudPromPassword = {
        reference = "op://cache/Grafana-Alloy/GRAFANA_CLOUD_PROM_PASSWORD";
        path = "/run/secrets/grafana-cloud-prom-password";
        mode = "0400";
        owner = config.systemd.services.grafana-alloy.serviceConfig.User or "root";
        group = config.systemd.services.grafana-alloy.serviceConfig.Group or "root";
        services = ["grafana-alloy"];
      };

      grafanaCloudLokiUrl = {
        reference = "op://cache/Grafana-Alloy/GRAFANA_CLOUD_LOKI_URL";
        path = "/run/secrets/grafana-cloud-loki-url";
        mode = "0400";
        owner = config.systemd.services.grafana-alloy.serviceConfig.User or "root";
        group = config.systemd.services.grafana-alloy.serviceConfig.Group or "root";
        services = ["grafana-alloy"];
      };

      grafanaCloudLokiUsername = {
        reference = "op://cache/Grafana-Alloy/GRAFANA_CLOUD_LOKI_USERNAME";
        path = "/run/secrets/grafana-cloud-loki-username";
        mode = "0400";
        owner = config.systemd.services.grafana-alloy.serviceConfig.User or "root";
        group = config.systemd.services.grafana-alloy.serviceConfig.Group or "root";
        services = ["grafana-alloy"];
      };

      grafanaCloudLokiPassword = {
        reference = "op://cache/Grafana-Alloy/GRAFANA_CLOUD_LOKI_PASSWORD";
        path = "/run/secrets/grafana-cloud-loki-password";
        mode = "0400";
        owner = config.systemd.services.grafana-alloy.serviceConfig.User or "root";
        group = config.systemd.services.grafana-alloy.serviceConfig.Group or "root";
        services = ["grafana-alloy"];
      };
    };

    systemdIntegration = {
      enable = true;
      services = ["grafana-alloy"];
      restartOnChange = true;
      changeDetection.enable = true;
    };
  };
}
