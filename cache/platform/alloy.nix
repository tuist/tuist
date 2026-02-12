{
  config,
  pkgs,
  ...
}: let
  grafanaCloudUrl = config.services.onepassword-secrets.secrets.grafanaCloudPromRemoteWriteUrl.path;
  grafanaCloudUsername = config.services.onepassword-secrets.secrets.grafanaCloudPromUsername.path;
  grafanaCloudPassword = config.services.onepassword-secrets.secrets.grafanaCloudPromPassword.path;

  grafanaCloudTempoUrl = config.services.onepassword-secrets.secrets.grafanaCloudTempoUrl.path;
  grafanaCloudTempoUsername = config.services.onepassword-secrets.secrets.grafanaCloudTempoUsername.path;
  grafanaCloudTempoPassword = config.services.onepassword-secrets.secrets.grafanaCloudTempoPassword.path;

  grafanaCloudLokiUrl = config.services.onepassword-secrets.secrets.grafanaCloudLokiUrl.path;
  grafanaCloudLokiUsername = config.services.onepassword-secrets.secrets.grafanaCloudLokiUsername.path;
  grafanaCloudLokiPassword = config.services.onepassword-secrets.secrets.grafanaCloudLokiPassword.path;

  alloyConfig = ''
    local.file "grafana_cloud_url" {
      filename = "${grafanaCloudUrl}"
    }

    local.file "grafana_cloud_username" {
      filename = "${grafanaCloudUsername}"
    }

    local.file "grafana_cloud_password" {
      filename = "${grafanaCloudPassword}"
      is_secret = true
    }

    local.file "grafana_cloud_tempo_url" {
      filename = "${grafanaCloudTempoUrl}"
    }

    local.file "grafana_cloud_tempo_username" {
      filename = "${grafanaCloudTempoUsername}"
    }

    local.file "grafana_cloud_tempo_password" {
      filename = "${grafanaCloudTempoPassword}"
      is_secret = true
    }

    local.file "grafana_cloud_loki_url" {
      filename = "${grafanaCloudLokiUrl}"
    }

    local.file "grafana_cloud_loki_username" {
      filename = "${grafanaCloudLokiUsername}"
    }

    local.file "grafana_cloud_loki_password" {
      filename = "${grafanaCloudLokiPassword}"
      is_secret = true
    }

    prometheus.remote_write "grafana_cloud" {
      endpoint {
        url = local.file.grafana_cloud_url.content

        basic_auth {
          username = local.file.grafana_cloud_username.content
          password = local.file.grafana_cloud_password.content
        }
      }
    }

    prometheus.exporter.unix "default" {
      include_exporter_metrics = true
      disable_collectors = []
      enable_collectors = ["filefd"]
    }

    prometheus.exporter.process "default" {
      track_children = false
      procfs_path = "/proc"
      track_threads = false

      matcher {
        comm = ["nginx"]
      }

      matcher {
        comm = ["beam.smp"]
        name = "cache"
      }
    }

    prometheus.scrape "process_exporter" {
      targets = prometheus.exporter.process.default.targets

      scrape_interval = "15s"

      forward_to = [prometheus.relabel.process_exporter.receiver]
    }

    prometheus.relabel "process_exporter" {
      rule {
        target_label = "instance"
        replacement  = "${config.networking.hostName}"
      }

      forward_to = [prometheus.remote_write.grafana_cloud.receiver]
    }

    prometheus.scrape "cache_promex" {
      targets = [
        {
          __address__ = "127.0.0.1:80",
          __scheme__ = "http",
          __metrics_path__ = "/metrics",
          instance = "${config.networking.hostName}",
        },
      ]

      scrape_interval = "15s"

      forward_to = [prometheus.remote_write.grafana_cloud.receiver]
    }

    prometheus.scrape "unix_exporter" {
      targets = prometheus.exporter.unix.default.targets

      scrape_interval = "15s"

      forward_to = [prometheus.relabel.unix_exporter.receiver]
    }

    prometheus.relabel "unix_exporter" {
      rule {
        target_label = "instance"
        replacement  = "${config.networking.hostName}"
      }

      forward_to = [prometheus.remote_write.grafana_cloud.receiver]
    }

    discovery.docker "linux" {
      host = "unix:///var/run/docker.sock"
    }

    loki.source.docker "default" {
      host       = "unix:///var/run/docker.sock"
      targets    = discovery.docker.linux.targets
      labels     = {
        app = "cache-docker",
        instance = "${config.networking.hostName}",
      }
      forward_to = [loki.write.grafana_cloud.receiver]
    }

    loki.source.file "nginx_error" {
      targets    = [
        {
          __path__  = "/var/log/nginx/error.log",
          job       = "cache-nginx",
          stream    = "error",
          instance  = "${config.networking.hostName}",
        },
      ]
      forward_to = [loki.write.grafana_cloud.receiver]
    }

    loki.source.file "nginx_access" {
      targets    = [
        {
          __path__  = "/var/log/nginx/access.log",
          job       = "cache-nginx",
          stream    = "access",
          instance  = "${config.networking.hostName}",
        },
      ]
      forward_to = [loki.process.nginx_access.receiver]
    }

    loki.process "nginx_access" {
      // Extract status code from log line
      stage.regex {
        expression = "\" (?P<status>\\d{3}) "
      }

      // Sample 2xx responses - keep 10%
      stage.match {
        selector = "{status=~\"2..\"}"

        stage.sampling {
          rate = 0.1
        }
      }

      // Drop status label to avoid high cardinality
      stage.label_drop {
        values = ["status"]
      }

      forward_to = [loki.write.grafana_cloud.receiver]
    }

    loki.write "grafana_cloud" {
      endpoint {
        url = local.file.grafana_cloud_loki_url.content

        basic_auth {
          username = local.file.grafana_cloud_loki_username.content
          password = local.file.grafana_cloud_loki_password.content
        }
      }
    }

    loki.source.api "default" {
      http {
        listen_address = "127.0.0.1"
        listen_port    = 3100
      }
      forward_to             = [loki.write.grafana_cloud.receiver]
      use_incoming_timestamp = true
    }

    otelcol.receiver.otlp "default" {
      grpc {
        endpoint = "127.0.0.1:4317"
      }

      output {
        traces = [otelcol.processor.batch.default.input]
      }
    }

    otelcol.auth.basic "grafana_cloud_tempo" {
      username = local.file.grafana_cloud_tempo_username.content
      password = local.file.grafana_cloud_tempo_password.content
    }

    otelcol.exporter.otlp "grafana_cloud_tempo" {
      client {
        endpoint = local.file.grafana_cloud_tempo_url.content
        auth     = otelcol.auth.basic.grafana_cloud_tempo.handler
      }
    }

    otelcol.processor.batch "default" {
      output {
        traces = [otelcol.exporter.otlp.grafana_cloud_tempo.input]
      }
    }
  '';
in {
  users.users.grafana-alloy = {
    isSystemUser = true;
    group = "grafana-alloy";
    description = "Grafana Alloy service user";
  };

  users.groups.grafana-alloy = {};

  environment.etc."grafana/alloy/config.alloy" = {
    mode = "0444";
    text = alloyConfig;
  };

  systemd.services.grafana-alloy = {
    description = "Grafana Alloy agent";
    wantedBy = ["multi-user.target"];
    after = ["onepassword-secrets.service"];

    serviceConfig = {
      ExecStart = "${pkgs.grafana-alloy}/bin/alloy run /etc/grafana/alloy/config.alloy --storage.path=/var/lib/grafana-alloy";
      Restart = "on-failure";
      RestartSec = 5;
      User = "grafana-alloy";
      Group = "grafana-alloy";
      StateDirectory = "grafana-alloy";
      SupplementaryGroups = ["keys" "systemd-journal" "docker" "nginx"];
    };
  };
}
