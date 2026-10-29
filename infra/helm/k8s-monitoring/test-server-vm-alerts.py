# /// script
# dependencies = ["jinja2>=3.1,<4"]
# ///
"""Validate notification-free Grafana and IRM routing (requires amtool)."""

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

from jinja2.sandbox import SandboxedEnvironment

DIRECTORY = Path(__file__).parent
RULES = json.loads((DIRECTORY / "server-vm-alert-rules.json").read_text())
ROUTE = json.loads((DIRECTORY / "server-vm-incident-route.json").read_text())
POLICY = json.loads((DIRECTORY / "server-vm-notification-route.json").read_text())


class IncidentRoutingTest(unittest.TestCase):
    def test_only_the_production_multi_pod_alert_escalates(self):
        template = SandboxedEnvironment().from_string(ROUTE["filtering_term"])
        warning, incident = RULES
        labels = {"alertname": incident["title"], **incident["labels"]}

        cases = [
            ("production incident", labels, True, "Incidents"),
            (
                "single-pod warning",
                {"alertname": warning["title"], **warning["labels"]},
                False,
                "Slack #notifications 2",
            ),
            (
                "staging",
                {**labels, "cluster": "tuist-staging"},
                False,
                "Slack #notifications-non-prod",
            ),
            (
                "canary",
                {**labels, "cluster": "tuist-canary"},
                False,
                "Slack #notifications 2",
            ),
            (
                "staging exception",
                {**labels, "env": "staging"},
                True,
                "Slack #notifications-non-prod",
            ),
            (
                "other folder",
                {**labels, "grafana_folder": "Other"},
                True,
                "Slack #notifications 2",
            ),
            (
                "missing cluster",
                {key: value for key, value in labels.items() if key != "cluster"},
                False,
                "Slack #notifications 2",
            ),
            (
                "wrong severity",
                {**labels, "severity": "warning"},
                False,
                "Slack #notifications 2",
            ),
            (
                "other alert",
                {**labels, "alertname": "Unrelated alert"},
                False,
                "Slack #notifications 2",
            ),
            (
                "datasource error",
                {
                    **labels,
                    "alertname": "DatasourceError",
                    "rulename": incident["title"],
                },
                False,
                "Slack #notifications 2",
            ),
            (
                "datasource no data",
                {
                    **labels,
                    "alertname": "DatasourceNoData",
                    "rulename": incident["title"],
                },
                False,
                "Slack #notifications 2",
            ),
            ("no common labels", None, False, "Slack #notifications 2"),
        ]
        # Use Alertmanager's engine, including the Slack fallback, not just the
        # IRM predicate: rejection by IRM's custom route still reaches on-call.
        policy = {
            key: value for key, value in POLICY.items() if key != "object_matchers"
        }
        policy["matchers"] = [
            f"{key}{operator}{json.dumps(value)}"
            for key, operator, value in POLICY["object_matchers"]
        ]
        config = {
            "route": {
                "receiver": "Slack #notifications 2",
                "routes": [
                    {
                        "receiver": "Slack #notifications-non-prod",
                        "matchers": ['cluster="tuist-staging"'],
                    },
                    {
                        "receiver": "Slack #notifications-non-prod",
                        "matchers": ['env="staging"'],
                    },
                    policy,
                ],
            },
            "receivers": [
                {"name": receiver}
                for receiver in [
                    "Slack #notifications 2",
                    "Slack #notifications-non-prod",
                    "Incidents",
                ]
            ],
        }
        with tempfile.TemporaryDirectory() as directory:
            config_path = Path(directory) / "routing.json"
            config_path.write_text(json.dumps(config))
            for name, common_labels, expected, receiver in cases:
                with self.subTest(name=name):
                    payload = (
                        {} if common_labels is None else {"commonLabels": common_labels}
                    )
                    self.assertEqual(template.render(payload=payload), str(expected))
                    notification_labels = {
                        "grafana_folder": "Alerts",
                        **(common_labels or {}),
                    }
                    result = subprocess.run(
                        [
                            "amtool",
                            "config",
                            "routes",
                            "test",
                            f"--config.file={config_path}",
                            f"--verify.receivers={receiver}",
                            *[
                                f"{key}={json.dumps(value)}"
                                for key, value in notification_labels.items()
                            ],
                        ],
                        capture_output=True,
                        text=True,
                        check=False,
                    )
                    self.assertEqual(
                        result.returncode, 0, result.stdout + result.stderr
                    )

    def test_only_the_multi_pod_alert_selects_incidents(self):
        warning, incident = RULES
        self.assertNotIn("notification_settings", warning)
        self.assertNotIn("notification_settings", incident)
        self.assertNotIn("affected_service", warning["labels"])
        self.assertEqual(POLICY["receiver"], "Incidents")
        self.assertEqual(POLICY["group_wait"], "0s")
        self.assertIn("cluster", POLICY["group_by"])
        self.assertEqual(incident["labels"]["affected_service"], "API")
        self.assertEqual(ROUTE["alert_receive_channel"], "CJNAYAYZBPKHL")
        self.assertEqual(ROUTE["escalation_chain"], "F7SJQ2LZ2T845")

    def test_failure_thresholds_and_recovery_holds(self):
        for rule, threshold, hold in zip(RULES, [0, 1], ["5m", "15m"], strict=True):
            with self.subTest(rule=rule["uid"]):
                condition = next(
                    item for item in rule["data"] if item["refId"] == rule["condition"]
                )
                self.assertEqual(
                    condition["model"]["conditions"][0]["evaluator"],
                    {"type": "gt", "params": [threshold]},
                )
                self.assertEqual(rule["for"], "0s")
                self.assertEqual(rule["keep_firing_for"], hold)
                self.assertEqual(rule["execErrState"], "Error")
                self.assertFalse(rule["isPaused"])


if __name__ == "__main__":
    unittest.main()
