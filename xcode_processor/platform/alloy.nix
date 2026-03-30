{ config, pkgs, ... }:

let
  alloyConfig = pkgs.writeText "alloy-config.alloy" ''
    prometheus.exporter.self "alloy" {
    }

    prometheus.scrape "alloy" {
      targets    = prometheus.exporter.self.alloy.targets
      forward_to = [prometheus.remote_write.grafana_cloud.receiver]
      scrape_interval = "60s"
    }

    prometheus.scrape "xcode_processor" {
      targets = [
        {"__address__" = "127.0.0.1:4003", "job" = "xcode-processor"},
      ]
      forward_to = [prometheus.remote_write.grafana_cloud.receiver]
      metrics_path = "/metrics"
      scrape_interval = "15s"
    }

    prometheus.remote_write "grafana_cloud" {
      endpoint {
        url = sys.env("GRAFANA_PROMETHEUS_REMOTE_WRITE_URL")

        basic_auth {
          username = sys.env("GRAFANA_PROMETHEUS_REMOTE_WRITE_USERNAME")
          password = sys.env("GRAFANA_PROMETHEUS_REMOTE_WRITE_PASSWORD")
        }
      }
    }

    loki.write "grafana_cloud" {
      endpoint {
        url = sys.env("GRAFANA_LOKI_URL")

        basic_auth {
          username = sys.env("GRAFANA_LOKI_USERNAME")
          password = sys.env("GRAFANA_LOKI_PASSWORD")
        }
      }
    }

    otelcol.receiver.otlp "default" {
      grpc {
        endpoint = "127.0.0.1:4317"
      }

      output {
        traces = [otelcol.processor.batch.default.input]
      }
    }

    otelcol.processor.batch "default" {
      output {
        traces = [otelcol.exporter.otlphttp.grafana_cloud.input]
      }
    }

    otelcol.exporter.otlphttp "grafana_cloud" {
      client {
        endpoint = sys.env("GRAFANA_TEMPO_URL")
        auth     = otelcol.auth.basic.grafana_cloud.handler
      }
    }

    otelcol.auth.basic "grafana_cloud" {
      username = sys.env("GRAFANA_TEMPO_USERNAME")
      password = sys.env("GRAFANA_TEMPO_PASSWORD")
    }
  '';

  alloyEnvScript = pkgs.writeScript "grafana-alloy-env" ''
    #!/bin/bash
    export GRAFANA_PROMETHEUS_REMOTE_WRITE_URL="$(cat ${config.sops.secrets.grafana_prometheus_remote_write_url.path})"
    export GRAFANA_PROMETHEUS_REMOTE_WRITE_USERNAME="$(cat ${config.sops.secrets.grafana_prometheus_remote_write_username.path})"
    export GRAFANA_PROMETHEUS_REMOTE_WRITE_PASSWORD="$(cat ${config.sops.secrets.grafana_prometheus_remote_write_password.path})"
    export GRAFANA_TEMPO_URL="$(cat ${config.sops.secrets.grafana_tempo_url.path})"
    export GRAFANA_TEMPO_USERNAME="$(cat ${config.sops.secrets.grafana_tempo_username.path})"
    export GRAFANA_TEMPO_PASSWORD="$(cat ${config.sops.secrets.grafana_tempo_password.path})"
    export GRAFANA_LOKI_URL="$(cat ${config.sops.secrets.grafana_loki_url.path})"
    export GRAFANA_LOKI_USERNAME="$(cat ${config.sops.secrets.grafana_loki_username.path})"
    export GRAFANA_LOKI_PASSWORD="$(cat ${config.sops.secrets.grafana_loki_password.path})"
    exec ${pkgs.grafana-alloy}/bin/alloy run ${alloyConfig}
  '';
in
{
  launchd.daemons."grafana-alloy" = {
    serviceConfig = {
      ProgramArguments = [ "${alloyEnvScript}" ];
      KeepAlive = true;
      RunAtLoad = true;
      StandardOutPath = "/var/log/grafana-alloy/stdout.log";
      StandardErrorPath = "/var/log/grafana-alloy/stderr.log";
    };
  };
}
