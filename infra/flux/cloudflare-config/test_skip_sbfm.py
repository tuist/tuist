"""Regression coverage for the project-root SBFM exemption, without API access."""

import pathlib
import re
import unittest


PATH_FIELD = "http.request.uri.path"


def root_conditions():
    rule = pathlib.Path(__file__).with_name("skip-sbfm-api-paths.yaml").read_text()
    clause = re.search(
        r'    \(\n(      http.request.method in .*?)\n    \) or', rule, re.DOTALL
    )
    if clause is None:
        raise AssertionError("Missing guarded project-root exemption")
    return [line.strip().removesuffix(" and") for line in clause.group(1).splitlines()]


def evaluate(condition, method, path):
    negated = condition.startswith("not ")
    if negated:
        condition = condition.removeprefix("not ")

    if match := re.fullmatch(r'http.request.method in \{(.*?)\}', condition):
        value = method in re.findall(r'"([^"]+)"', match[1])
    elif match := re.fullmatch(re.escape(PATH_FIELD) + r' wildcard "([^"]+)"', condition):
        # Cloudflare wildcards match the entire string, including slashes,
        # and are case insensitive. They are not filesystem globs.
        pattern = re.escape(match[1]).replace(r"\*", ".*")
        value = re.fullmatch(pattern, path, re.IGNORECASE) is not None
    elif match := re.fullmatch(
        r'(starts_with|ends_with)\(' + re.escape(PATH_FIELD) + r', "([^"]+)"\)',
        condition,
    ):
        value = path.startswith(match[2]) if match[1] == "starts_with" else path.endswith(match[2])
    elif match := re.fullmatch(re.escape(PATH_FIELD) + r' contains "([^"]+)"', condition):
        value = match[1] in path
    else:
        raise AssertionError(f"Unrecognized root guard: {condition}")

    return not value if negated else value


class ProjectRootExemptionTest(unittest.TestCase):
    def exempt(self, path, method="GET"):
        return all(evaluate(condition, method, path) for condition in root_conditions())

    def test_canonical_project_roots(self):
        for path in ["/tuist/tuist", "/tuist/ios_app_with_frameworks", "/my-org/my_project"]:
            for method in ["GET", "HEAD"]:
                with self.subTest(path=path, method=method):
                    self.assertTrue(self.exempt(path, method))

    def test_deeper_dashboards_and_empty_segments_remain_protected(self):
        for path in [
            "/tuist/tuist/analytics", "/tuist/tuist/builds", "/tuist/tuist/tests/test-runs",
            "/tuist/tuist/", "/tuist/", "//tuist", "//", "/tuist//tuist", "/tuist",
        ]:
            with self.subTest(path=path):
                self.assertFalse(self.exempt(path))

    def test_sockets_authentication_operator_and_scanner_paths_remain_protected(self):
        for path in [
            "/live/websocket", "/live/longpoll", "/socket/websocket", "/users/log_in",
            "/users/register", "/auth/callback", "/ops/og-gallery", "/.git/config",
            "/wp-admin/install.php", "/tuist/tuist%2Fbuilds",
        ]:
            with self.subTest(path=path):
                self.assertFalse(self.exempt(path))

    def test_non_read_methods_remain_protected(self):
        for method in ["POST", "PUT", "PATCH", "DELETE"]:
            self.assertFalse(self.exempt("/tuist/tuist", method))


if __name__ == "__main__":
    unittest.main()
