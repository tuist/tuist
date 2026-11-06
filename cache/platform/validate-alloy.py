#!/usr/bin/env python3
"""Render every cache host and validate fan-out without credentials or network.

Requires Nix and Docker with grafana/alloy:v<Nix package version> already pulled.
Set DOCKER_BIN if Docker is not on PATH. No opnix service is started.
"""

import json
import os
import re
import subprocess
import tempfile
import time
from pathlib import Path


def run(*args):
    return subprocess.check_output(args, text=True)


def components(config):
    return {
        (kind, name): body
        for kind, name, body in re.findall(
            r'^([\w.]+) "([\w]+)" \{\n(.*?)^\}', config, re.MULTILINE | re.DOTALL
        )
    }


def validate_runtime(docker, image, config, directory):
    # `alloy validate` does not compile LogQL match selectors. Start the full
    # graph once, with fake files and no network, to catch stage construction
    # errors too. All hosts share these processing stages.
    for filename in re.findall(r'filename = "([^"]+)"', config):
        name = Path(filename).name
        value = "fixture"
        if name.endswith("url"):
            value = "127.0.0.1:9" if "tempo" in name else "http://127.0.0.1:9/ingest"
        (directory / name).write_text(value)
        config = config.replace(filename, f"/fixtures/{name}")
    config = re.sub(r'https://pulse[^/"]*', "http://127.0.0.1:9", config)
    (directory / "runtime.alloy").write_text(config)
    container = run(
        docker,
        "run",
        "-d",
        "--pull=never",
        "--network=none",
        "-v",
        f"{directory}:/fixtures:ro",
        image,
        "run",
        "/fixtures/runtime.alloy",
        "--storage.path=/tmp/alloy",
        "--disable-reporting",
    ).strip()
    try:
        time.sleep(2)
        logs = subprocess.check_output(
            [docker, "logs", container], text=True, stderr=subprocess.STDOUT
        )
        running = run(docker, "inspect", "--format={{.State.Running}}", container)
        assert running.strip() == "true", logs
        assert "failed to evaluate config" not in logs, logs
        assert "invalid stage config" not in logs, logs
        print("PASS full graph startup with fake secrets and networking disabled")
    finally:
        run(docker, "stop", "--time=3", container)
        run(docker, "rm", container)


def main():
    root = Path(__file__).resolve().parents[1]
    configs = json.loads(
        run(
            "nix",
            "eval",
            "--json",
            f"{root}/platform#nixosConfigurations",
            "--apply",
            """builtins.mapAttrs (_: system: {
              alloy = system.config.environment.etc."grafana/alloy/config.alloy".text;
              token = system.config.services.onepassword-secrets.secrets.pulseToken;
              alloyVersion = system.pkgs.grafana-alloy.version;
              alloyPackage = toString system.pkgs.grafana-alloy;
              execStart = system.config.systemd.services.grafana-alloy.serviceConfig.ExecStart;
            })""",
        )
    )
    docker = os.environ.get("DOCKER_BIN", "docker")
    versions = {c["alloyVersion"] for c in configs.values()}
    assert len(versions) == 1, f"Hosts select different Alloy versions: {versions}"
    version = versions.pop()
    assert re.fullmatch(r"\d+\.\d+\.\d+", version), version
    image = f"grafana/alloy:v{version}"
    reported = run(
        docker, "run", "--rm", "--pull=never", "--network=none", image, "--version"
    )
    assert re.search(rf"\bversion v?{re.escape(version)}\b", reported), reported
    print(f"Nix-selected Alloy {version}; Docker binary: {reported.strip()}")
    with tempfile.TemporaryDirectory(prefix="cache-alloy-validation-") as tmp:
        for hostname, rendered in configs.items():
            assert rendered["execStart"].startswith(
                f'{rendered["alloyPackage"]}/bin/alloy run '
            ), rendered["execStart"]
            env = next(
                (e for e in ("staging", "canary") if hostname.endswith(f"-{e}")),
                "production",
            )
            url = (
                "https://pulse.tuist.dev"
                if env == "production"
                else f"https://pulse-{env}.tuist.dev"
            )
            config = rendered["alloy"]
            blocks = components(config)
            token = rendered["token"]
            assert token["reference"] == f"op://tuist-k8s-{env}/PULSE_TOKEN/password"
            assert token["mode"] == "0400"
            assert token["owner"] == token["group"] == "grafana-alloy"
            assert token["services"] == ["grafana-alloy"]
            assert (
                f'filename = "{token["path"]}"' in blocks["local.file", "pulse_token"]
            )
            assert "is_secret = true" in blocks["local.file", "pulse_token"]

            metrics = [
                ("prometheus.scrape", "cache_promex"),
                *(
                    ("prometheus.relabel", n)
                    for n in ("process_exporter", "unix_exporter", "alloy")
                ),
            ]
            logs = [
                ("loki.source.file", "nginx_error"),
                *(
                    ("loki.process", n)
                    for n in ("cache_docker", "nginx_access", "cache_api")
                ),
            ]
            for pipelines, writer in (
                (metrics, "prometheus.remote_write"),
                (logs, "loki.write"),
            ):
                for pipeline in pipelines:
                    assert (
                        f"forward_to = [{writer}.grafana_cloud.receiver, {writer}.pulse.receiver]"
                        in blocks[pipeline]
                    )
                destination = blocks[writer, "pulse"]
                assert f'cluster = "tuist-{env}"' in destination
                assert f'env = "{env}"' in destination
                path = (
                    "/api/v1/write"
                    if writer.startswith("prometheus")
                    else "/loki/api/v1/push"
                )
                assert f'url = "{url}{path}"' in destination
                assert 'username = "tuist"' in destination
                assert "password = local.file.pulse_token.content" in destination
                assert "pulse" not in blocks[writer, "grafana_cloud"]

            assert (
                "traces = [otelcol.processor.batch.default.input, otelcol.processor.transform.pulse.input]"
                in blocks["otelcol.receiver.otlp", "default"]
            )
            assert (
                "otelcol.exporter.otlp.grafana_cloud_tempo.input"
                in blocks["otelcol.processor.batch", "default"]
            )
            assert "pulse" not in blocks["otelcol.processor.batch", "default"]
            assert "pulse" not in blocks["otelcol.exporter.otlp", "grafana_cloud_tempo"]
            batch = blocks["otelcol.processor.batch", "pulse"]
            assert "send_batch_size = 2048" in batch
            assert "send_batch_max_size = 2048" in batch
            assert f'endpoint = "{url}"' in blocks["otelcol.exporter.otlphttp", "pulse"]
            graph = blocks["otelcol.exporter.prometheus", "pulse_servicegraph"]
            assert "add_metric_suffixes = false" in graph
            assert (
                "forward_to = [prometheus.relabel.pulse_servicegraph.receiver]" in graph
            )
            identity = blocks["prometheus.relabel", "pulse_servicegraph"]
            assert f'replacement = "{hostname}"' in identity
            assert "forward_to = [prometheus.remote_write.pulse.receiver]" in identity

            path = Path(tmp) / f"{hostname}.alloy"
            path.write_text(config)
            run(
                docker,
                "run",
                "--rm",
                "--pull=never",
                "--network=none",
                "-v",
                f"{path}:/etc/alloy/config.alloy:ro",
                image,
                "validate",
                "/etc/alloy/config.alloy",
            )
            print(
                f"PASS {hostname}: fan-out, labels, secret metadata, Alloy {version} validation"
            )
        validate_runtime(docker, image, config, Path(tmp))


if __name__ == "__main__":
    main()
