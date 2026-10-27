#!/usr/bin/env python3
"""Check explicit SSO DNS policy in rendered charts without runtime secrets."""

import re
import subprocess
import unittest
from pathlib import Path

CHART = Path(__file__).resolve().parent
ENVIRONMENT_VARIABLE = "TUIST_SSO_REQUIRE_LOGIN_DOMAIN_VERIFICATION"
TEMPLATES = (
    "server-deployment.yaml",
    "processor-deployment.yaml",
    "xcresult-processor-deployment.yaml",
    "swift-registry-sync-deployment.yaml",
    "server-migration-job.yaml",
)


class SSODomainVerificationTests(unittest.TestCase):
    def assert_policy(self, values, required, overrides=(), separate_processor=False):
        chart = CHART.parent / "xcresult-processor" if separate_processor else CHART
        command = ["helm", "template", "sso-validation", str(chart)]
        for value in (*values, "values-ci.yaml"):
            command.extend(["-f", str(CHART / value)])
        settings = [
            "processor.enabled=true",
            "swiftRegistrySync.enabled=true",
            "xcresultProcessor.enabled=true",
            "server.migrationJob.enabled=true",
            f"xcresultProcessor.ownRelease={str(separate_processor).lower()}",
            *overrides,
        ]
        if separate_processor:
            settings.append("tuistRelease=sso-validation")
        for setting in settings:
            command.extend(["--set", setting])
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, "Helm rendering failed (output suppressed)")
        templates = ("xcresult-processor-deployment.yaml",) if separate_processor else TEMPLATES
        for template in templates:
            with self.subTest(template=template):
                doc = next((doc for doc in result.stdout.split("---\n")
                            if f"/templates/{template}\n" in doc
                            and re.search(r"^kind: (Deployment|Job)$", doc, re.M)), "")
                self.assertTrue(doc, "Expected runtime template was not rendered")
                flags = re.findall(rf'- name: {ENVIRONMENT_VARIABLE}\s+value: "(true|false)"', doc)
                self.assertEqual(flags, [str(required).lower()])

    def test_self_hosted_defaults_to_no_dns_verification(self):
        self.assert_policy(["values-self-hosted-ci.yaml"], False)

    def test_self_hosted_can_explicitly_require_dns_verification(self):
        self.assert_policy(["values-self-hosted-ci.yaml"], True,
                           ["server.ssoRequireLoginDomainVerification=true"])

    def test_hosted_mode_alone_does_not_enable_dns_verification(self):
        self.assert_policy(["values-self-hosted-ci.yaml"], False, ["server.hosted=true"])

    def test_managed_environments_explicitly_require_dns_verification(self):
        for environment in ("staging", "canary", "production"):
            with self.subTest(environment=environment):
                self.assert_policy(["values-managed-common.yaml", f"values-managed-{environment}.yaml"], True)

    def test_previews_and_pentest_explicitly_require_dns_verification(self):
        for values in (["values-preview.yaml", "values-preview-kura.yaml", "values-preview-ci.yaml"],
                       ["values-pentest.yaml"]):
            with self.subTest(values=values):
                self.assert_policy(values, True)

    def test_separate_xcresult_processor_inherits_managed_policy(self):
        for environment in ("staging", "canary", "production"):
            with self.subTest(environment=environment):
                self.assert_policy(["values-managed-common.yaml", f"values-managed-{environment}.yaml"],
                                   True, separate_processor=True)


if __name__ == "__main__":
    unittest.main()
