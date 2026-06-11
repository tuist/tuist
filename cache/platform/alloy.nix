{
  config,
  lib,
  pkgs,
  ...
}: let
  hostName = config.networking.hostName;
  isNonProduction = lib.hasSuffix "-staging" hostName || lib.hasSuffix "-canary" hostName;
  cachePromexScrapeInterval = if isNonProduction then "120s" else "30s";
  internalExporterScrapeInterval = if isNonProduction then "60s" else "30s";

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

    prometheus.exporter.self "alloy" {}

    prometheus.exporter.unix "default" {
      include_exporter_metrics = false
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

      scrape_interval = "${internalExporterScrapeInterval}"

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

      scrape_interval = "${cachePromexScrapeInterval}"

      forward_to = [prometheus.remote_write.grafana_cloud.receiver]
    }

    prometheus.scrape "unix_exporter" {
      targets = prometheus.exporter.unix.default.targets

      scrape_interval = "${internalExporterScrapeInterval}"

      forward_to = [prometheus.relabel.unix_exporter.receiver]
    }

    prometheus.relabel "unix_exporter" {
      rule {
        target_label = "instance"
        replacement  = "${config.networking.hostName}"
      }

      forward_to = [prometheus.remote_write.grafana_cloud.receiver]
    }

    prometheus.scrape "alloy" {
      targets = prometheus.exporter.self.alloy.targets

      scrape_interval = "${internalExporterScrapeInterval}"

      forward_to = [prometheus.relabel.alloy.receiver]
    }

    prometheus.relabel "alloy" {
      rule {
        action        = "keep"
        source_labels = ["__name__"]
        regex         = "cache_nginx_.*"
      }

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
      // Extract request details so nginx can emit response-code metrics that
      // still include responses generated before a request reaches Phoenix.
      stage.regex {
        expression = "\"(?P<method>\\S+) (?P<request_path>\\S+) [^\"]+\" (?P<status>\\d{3}) .* rt=(?P<request_time>[0-9.]+)"
      }

      stage.regex {
        source = "status"
        expression = "^(?P<status_class>\\d)\\d\\d$"
      }

      stage.template {
        source   = "path_group"
        template = "other"
      }

      stage.match {
        selector = "{job=\"cache-nginx\"} |= \"/api/cache/cas/\""

        stage.template {
          source   = "path_group"
          template = "xcode"
        }
      }

      stage.match {
        selector = "{job=\"cache-nginx\"} |= \"/api/cache/keyvalue/\""

        stage.template {
          source   = "path_group"
          template = "keyvalue"
        }
      }

      stage.match {
        selector = "{job=\"cache-nginx\"} |= \"/api/cache/gradle/\""

        stage.template {
          source   = "path_group"
          template = "gradle"
        }
      }

      stage.match {
        selector = "{job=\"cache-nginx\"} |= \"/api/cache/module/\""

        stage.template {
          source   = "path_group"
          template = "module"
        }
      }

      stage.match {
        selector = "{job=\"cache-nginx\"} |= \"/api/registry/swift\""

        stage.template {
          source   = "path_group"
          template = "registry"
        }
      }

      stage.match {
        selector = "{job=\"cache-nginx\"} |= \" /metrics \""

        stage.template {
          source   = "path_group"
          template = "metrics"
        }
      }

      stage.template {
        source   = "method"
        template = "{{ if or (eq .method \"GET\") (eq .method \"HEAD\") (eq .method \"POST\") (eq .method \"PUT\") (eq .method \"DELETE\") (eq .method \"PATCH\") (eq .method \"OPTIONS\") (eq .method \"CONNECT\") (eq .method \"TRACE\") (eq .method \"PROPFIND\") }}{{ .method }}{{ else }}INVALID{{ end }}"
      }

      stage.labels {
        values = {
          method = "",
          path_group = "",
          status = "",
          status_class = "",
        }
      }

      stage.metrics {
        metric.counter {
          name        = "http_responses_total"
          description = "Total nginx responses by path group, method, and status"
          prefix      = "cache_nginx_"

          match_all         = true
          action            = "inc"
          max_idle_duration = "24h"
        }
      }

      stage.metrics {
        metric.histogram {
          name              = "request_duration_seconds"
          description       = "Nginx request duration by path group, method, and status"
          prefix            = "cache_nginx_"
          source            = "request_time"
          buckets           = [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30]
          max_idle_duration = "24h"
        }
      }

      // Sample successful responses to keep log volume manageable while still
      // preserving all response-code metrics above.
      stage.match {
        selector = "{status_class=\"2\"}"

        stage.sampling {
          rate = 0.1
        }
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
        listen_address = "0.0.0.0"
        listen_port    = 3100
      }
      forward_to             = [loki.write.grafana_cloud.receiver]
      use_incoming_timestamp = true
    }

    otelcol.receiver.otlp "default" {
      grpc {
        endpoint = "0.0.0.0:4317"
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
