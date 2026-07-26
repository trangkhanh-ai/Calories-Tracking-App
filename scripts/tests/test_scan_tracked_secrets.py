#!/usr/bin/env python3
"""Regression tests for the tracked-file secret scanner."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCANNER = Path(__file__).resolve().parents[1] / "scan_tracked_secrets.py"
HISTORICAL_NOTICE = (
    "Historical Gemini exposure: Yes\n"
    "Gemini key rotation required before production: Yes"
)


class ScannerTests(unittest.TestCase):
    def setUp(self) -> None:
        self._temporary_directory = tempfile.TemporaryDirectory()
        self.repo = Path(self._temporary_directory.name)
        self.run_git("init", "--quiet")
        self.run_git("config", "user.email", "scanner-tests@example.invalid")
        self.run_git("config", "user.name", "Scanner Tests")

    def tearDown(self) -> None:
        self._temporary_directory.cleanup()

    def run_git(self, *arguments: str, input_text: str | None = None) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["git", *arguments],
            cwd=self.repo,
            input=input_text,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        )

    def track(self, relative_path: str, content: str) -> None:
        path = self.repo / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        self.run_git("add", "--", relative_path)

    def scan(self) -> subprocess.CompletedProcess[str]:
        environment = os.environ.copy()
        environment["PYTHONUTF8"] = "1"
        result = subprocess.run(
            [sys.executable, str(SCANNER)],
            cwd=self.repo,
            env=environment,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        self.assertEqual("", result.stderr)
        self.assertIn(HISTORICAL_NOTICE, result.stdout)
        return result

    def test_enumerates_tracked_files_and_redacts_detected_value(self) -> None:
        secret = "JWT__KEY=tracked-value-that-must-never-be-printed-1234567890"  # secret-scan: test-fixture
        self.track("tracked.env", f"safe=true\n{secret}\n")

        result = self.scan()

        self.assertNotEqual(0, result.returncode)
        self.assertIn("JWT_KEY tracked.env:2 [REDACTED]", result.stdout)
        self.assertNotIn(secret, result.stdout)

    def test_ignores_untracked_dotenv_without_opening_it(self) -> None:
        self.track("tracked.txt", "safe=true\n")
        secret = "GEMINI__APIKEY=untracked-value-that-must-stay-private"  # secret-scan: test-fixture
        (self.repo / ".env").write_text(secret, encoding="utf-8")

        result = self.scan()

        self.assertEqual(0, result.returncode)
        self.assertNotIn(secret, result.stdout)

    def test_refuses_tracked_symlink_entries(self) -> None:
        target = self.repo / "outside.txt"
        target.write_text("safe=true\n", encoding="utf-8")
        blob = self.run_git("hash-object", "-w", "--stdin", input_text="outside.txt").stdout.strip()
        self.run_git("update-index", "--add", "--cacheinfo", f"120000,{blob},linked-secret")

        result = self.scan()

        self.assertNotEqual(0, result.returncode)
        self.assertIn("TRACKED_SYMLINK linked-secret:0 [REDACTED]", result.stdout)

    def test_accepts_documented_placeholder_forms(self) -> None:
        self.track(
            "placeholders.env",
            "\n".join(
                (
                    "JWT__KEY=<generated-at-runtime>",
                    "GEMINI__APIKEY=${gemini_api_key}",
                    "Password=${db_password}",
                    "postgresql://${PGUSER}:${PGPASSWORD}@postgres/calories",
                    "Jwt:Key=${{ secrets.JWT_KEY }}",
                    "GEMINI__APIKEY=${{ env.GEMINI_API_KEY }}",
                    "Password=${{ vars.POSTGRES_PASSWORD }}",
                    "Password=redacted",
                    "",
                )
            ),
        )

        result = self.scan()

        self.assertEqual(0, result.returncode)

    def test_accepts_explicitly_marked_test_fixture(self) -> None:
        secret = "AIzaSyFixtureValueOnly123456789012345678"  # secret-scan: test-fixture
        self.track("tests/fixture.txt", f"api_key={secret} # secret-scan: test-fixture\n")

        result = self.scan()

        self.assertEqual(0, result.returncode)
        self.assertNotIn(secret, result.stdout)

    def test_fixture_marker_cannot_bypass_scan_in_production_path(self) -> None:
        secret = "JWT__KEY=production-secret-that-must-be-redacted-1234567890"  # secret-scan: test-fixture
        self.track("production.env", f"{secret} # secret-scan: test-fixture\n")

        result = self.scan()

        self.assertNotEqual(0, result.returncode)
        self.assertIn("JWT_KEY production.env:1 [REDACTED]", result.stdout)
        self.assertNotIn(secret, result.stdout)

    def test_literal_prefix_with_shell_suffix_is_not_a_placeholder(self) -> None:
        secret = "Password=literal-secret-prefix${SAFE_SUFFIX}"  # secret-scan: test-fixture
        self.track("production.env", f"{secret}\n")

        result = self.scan()

        self.assertNotEqual(0, result.returncode)
        self.assertIn("PASSWORD production.env:1 [REDACTED]", result.stdout)
        self.assertNotIn(secret, result.stdout)

    def test_github_expression_with_literal_suffix_is_not_a_placeholder(self) -> None:
        password = "Password=${{ secrets.POSTGRES_PASSWORD }}literal-password-suffix"  # secret-scan: test-fixture
        jwt = "JWT__KEY=${{ env.JWT_KEY }}literal-jwt-suffix"  # secret-scan: test-fixture
        gemini = "GEMINI__APIKEY=${{ vars.GEMINI_KEY }}literal-gemini-suffix"  # secret-scan: test-fixture
        self.track("production.env", f"{password}\n{jwt}\n{gemini}\n")

        result = self.scan()

        self.assertNotEqual(0, result.returncode)
        self.assertEqual(
            [
                "PASSWORD production.env:1 [REDACTED]",
                "JWT_KEY production.env:2 [REDACTED]",
                "GEMINI_API_KEY production.env:3 [REDACTED]",
                *HISTORICAL_NOTICE.splitlines(),
            ],
            result.stdout.splitlines(),
        )
        for raw_suffix in (
            "literal-password-suffix",
            "literal-jwt-suffix",
            "literal-gemini-suffix",
        ):
            self.assertNotIn(raw_suffix, result.stdout)

    def test_ignores_source_property_assignments_and_pattern_declarations(self) -> None:
        self.track(
            "source.cs",
            "Password = request.Password;\n"
            "PASSWORD = re.compile(r'Password\\s*=');\n",
        )

        result = self.scan()

        self.assertEqual(0, result.returncode)

    def test_accepts_obvious_credentials_in_tracked_test_fixture_paths(self) -> None:
        self.track(
            "tests/connection_fixture.cs",
            'var connection = "Host=example.invalid;Password=test";\n'
            'var uri = "postgresql://fixture:p%40ssword@db.example.invalid/calories";\n',
        )

        result = self.scan()

        self.assertEqual(0, result.returncode)

    def test_detects_all_required_categories_without_printing_values(self) -> None:
        findings = (
            ("GOOGLE_API_KEY", "google.txt", "AIzaSyCurrentSecret123456789012345678901"),  # secret-scan: test-fixture
            ("PRIVATE_KEY", "private.pem", "-----BEGIN PRIVATE KEY-----"),  # secret-scan: test-fixture
            ("POSTGRES_URI_CREDENTIALS", "database.txt", "postgresql://app:uri-secret@db/calories"),  # secret-scan: test-fixture
            ("JWT_KEY", "jwt.json", '"Jwt:Key": "jwt-current-secret-value-1234567890"'),  # secret-scan: test-fixture
            ("GEMINI_API_KEY", "gemini.json", '"Gemini:ApiKey": "gemini-current-secret-value"'),  # secret-scan: test-fixture
            ("PASSWORD", "password.env", "Password=current-password-value"),  # secret-scan: test-fixture
        )
        for _, path, value in findings:
            self.track(path, f"{value}\n")

        result = self.scan()

        self.assertNotEqual(0, result.returncode)
        self.assertEqual(
            [
                "POSTGRES_URI_CREDENTIALS database.txt:1 [REDACTED]",
                "GEMINI_API_KEY gemini.json:1 [REDACTED]",
                "GOOGLE_API_KEY google.txt:1 [REDACTED]",
                "JWT_KEY jwt.json:1 [REDACTED]",
                "PASSWORD password.env:1 [REDACTED]",
                "PRIVATE_KEY private.pem:1 [REDACTED]",
                *HISTORICAL_NOTICE.splitlines(),
            ],
            result.stdout.splitlines(),
        )

        sensitive_tokens = (
            "AIzaSyCurrentSecret123456789012345678901",  # secret-scan: test-fixture
            "-----BEGIN PRIVATE KEY-----",  # secret-scan: test-fixture
            "postgresql://app:uri-secret@db/calories",  # secret-scan: test-fixture
            "uri-secret",
            "jwt-current-secret-value-1234567890",
            "gemini-current-secret-value",
            "current-password-value",
        )
        for sensitive_token in sensitive_tokens:
            self.assertNotIn(sensitive_token, result.stdout)


if __name__ == "__main__":
    unittest.main()
