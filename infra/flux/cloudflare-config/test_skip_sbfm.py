"""Regression coverage for SBFM exemption scope, without API access."""

import pathlib
import re
import unittest


PATH_FIELD = "http.request.uri.path"


def rule_expression():
    rule = pathlib.Path(__file__).with_name("skip-sbfm-api-paths.yaml").read_text()
    return rule.split("  expression: |-\n", 1)[1].split("\n  action:", 1)[0].strip()


def evaluate_expression(expression, method, path, host):
    # Split at the outermost boolean operators, respecting precedence and
    # parentheses in both groups and starts_with/ends_with calls.
    for operator, combine in [("or", any), ("and", all)]:
        depth = 0
        start = 0
        parts = []
        for token in re.finditer(r'"[^"]*"|\(|\)|\b(?:and|or)\b', expression):
            if token[0] == "(":
                depth += 1
            elif token[0] == ")":
                depth -= 1
            elif token[0] == operator and depth == 0:
                parts.append(expression[start:token.start()].strip())
                start = token.end()
        if parts:
            parts.append(expression[start:].strip())
            return combine(evaluate_expression(part, method, path, host) for part in parts)

    if expression.startswith("(") and expression.endswith(")"):
        return evaluate_expression(expression[1:-1].strip(), method, path, host)

    return evaluate(expression, method, path, host)


def evaluate(condition, method, path, host):
    negated = condition.startswith("not ")
    if negated:
        condition = condition.removeprefix("not ")

    fields = {PATH_FIELD: path, "http.request.method": method, "http.host": host}
    if match := re.fullmatch(r'(http\.[\w.]+) in \{(.*?)\}', condition):
        value = fields[match[1]] in re.findall(r'"([^"]+)"', match[2])
    elif match := re.fullmatch(r'(http\.[\w.]+) (eq|ne) "([^"]+)"', condition):
        value = fields[match[1]] == match[3]
        if match[2] == "ne":
            value = not value
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
        raise AssertionError(f"Unrecognized condition: {condition}")

    return not value if negated else value


class SbfmExemptionTest(unittest.TestCase):
    def exempt(self, path, method="GET", host="tuist.dev"):
        return evaluate_expression(rule_expression(), method, path, host)

    def test_canonical_project_roots(self):
        for path in ["/tuist/tuist", "/tuist/ios_app_with_frameworks", "/my-org/my_project"]:
            for method in ["GET", "HEAD"]:
                with self.subTest(path=path, method=method):
                    self.assertTrue(self.exempt(path, method))

    def test_public_documentation_and_markdown(self):
        paths = [
            "/docs", "/docs/en/guides/install-tuist",
            "/marketing-markdown", "/marketing-markdown/",
            "/marketing-markdown/cache", "/marketing-markdown/compare/github-actions",
            "/marketing-markdown/source/openness", "/robots.txt", "/llms.txt",
            "/llms-full.txt", "/sitemap.xml",
        ]
        for locale in ["en", "es", "ja", "ka", "ko", "ru", "yue_Hant", "zh_Hans", "zh_Hant"]:
            for section in ["docs", "docs-markdown"]:
                paths.extend([
                    f"/{locale}/{section}", f"/{locale}/{section}/",
                    f"/{locale}/{section}/guides/install-tuist",
                    f"/{locale}/{section}/references/docs/example",
                ])
        for path in paths:
            for method in ["GET", "HEAD"]:
                with self.subTest(path=path, method=method):
                    self.assertTrue(self.exempt(path, method))

    def test_content_prefixes_do_not_exempt_project_dashboards(self):
        for path in [
            "/tuist/docs/builds", "/tuist/docs-markdown/tests",
            "/tuist/en/docs/builds", "/en/tuist/docs/guides/install-tuist",
            "/en/docs-private/builds", "/en/docs-markdown-private/tests",
            "/marketing-markdown-private/compare/provider", "/docs-private/en/guides/install-tuist",
        ]:
            with self.subTest(path=path):
                self.assertFalse(self.exempt(path))

    def test_deeper_dashboards_and_empty_segments_remain_protected(self):
        for path in [
            "/tuist/tuist/analytics", "/tuist/tuist/builds", "/tuist/tuist/tests",
            "/tuist/tuist/module-cache", "/tuist/tuist/tests/test-runs",
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
        for path in [
            "/tuist/tuist", "/en/docs", "/en/docs/guides/install-tuist",
            "/en/docs-markdown/guides/install-tuist", "/marketing-markdown",
            "/marketing-markdown/cache", "/llms.txt",
        ]:
            for method in ["POST", "PUT", "PATCH", "DELETE", "OPTIONS"]:
                with self.subTest(path=path, method=method):
                    self.assertFalse(self.exempt(path, method))

    def test_existing_machine_paths_remain_exempt(self):
        for path, method in [
            ("/api/auth/oidc/token", "POST"), ("/webhooks/github", "POST"),
            ("/mcp", "POST"), ("/oauth2/token", "POST"),
            ("/scim/v2/Users", "PATCH"), ("/agent/auth/claim", "POST"),
            ("/open-graph-images/signed-key", "GET"),
            ("/tuist/tuist/previews/example/app.ipa", "GET"),
        ]:
            with self.subTest(path=path, method=method):
                self.assertTrue(self.exempt(path, method))
        self.assertTrue(self.exempt("/search", "POST", host="search.tuist.dev"))


if __name__ == "__main__":
    unittest.main()
