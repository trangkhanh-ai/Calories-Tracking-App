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

    def test_placeholder_first_match_does_not_hide_later_literal(self) -> None:
        uri = "postgresql://${PGUSER}:${PGPASSWORD}@postgres/calories postgresql://app:literal-uri-secret@db/calories"  # secret-scan: test-fixture
        jwt = "JWT__KEY=${JWT_KEY} JWT__KEY=literal-jwt-secret-1234567890"  # secret-scan: test-fixture
        gemini = "GEMINI__APIKEY=${GEMINI_KEY} GEMINI__APIKEY=literal-gemini-secret"  # secret-scan: test-fixture
        password = "Password=${DB_PASSWORD} Password=literal-password-secret"  # secret-scan: test-fixture
        self.track("production.env", f"{uri}\n{jwt}\n{gemini}\n{password}\n")

        result = self.scan()

        self.assertNotEqual(0, result.returncode)
        self.assertEqual(
            [
                "POSTGRES_URI_CREDENTIALS production.env:1 [REDACTED]",
                "JWT_KEY production.env:2 [REDACTED]",
                "GEMINI_API_KEY production.env:3 [REDACTED]",
                "PASSWORD production.env:4 [REDACTED]",
                *HISTORICAL_NOTICE.splitlines(),
            ],
            result.stdout.splitlines(),
        )
        for raw_secret in (
            "literal-uri-secret",
            "literal-jwt-secret-1234567890",
            "literal-gemini-secret",
            "literal-password-secret",
        ):
            self.assertNotIn(raw_secret, result.stdout)

    def test_detects_native_nested_json_and_yaml_configuration(self) -> None:
        json_jwt = "nested-json-jwt-secret-1234567890"  # secret-scan: test-fixture
        json_gemini = "nested-json-gemini-secret"  # secret-scan: test-fixture
        yaml_jwt = "nested-yaml-jwt-secret-1234567890"  # secret-scan: test-fixture
        yaml_gemini = "nested-yaml-gemini-secret"  # secret-scan: test-fixture
        self.track(
            "appsettings.json",
            "{\n"
            '  "Jwt": {\n'
            f'    "Key": "{json_jwt}"\n'
            "  },\n"
            f'  "Gemini": {{ "ApiKey": "{json_gemini}" }}\n'  # secret-scan: test-fixture
            "}\n",
        )
        self.track(
            "appsettings.yaml",
            "Jwt:\n"
            f"  Key: {yaml_jwt}\n"
            "Gemini:\n"
            f"  ApiKey: {yaml_gemini}\n",
        )

        result = self.scan()

        self.assertNotEqual(0, result.returncode)
        self.assertEqual(
            [
                "JWT_KEY appsettings.json:3 [REDACTED]",
                "GEMINI_API_KEY appsettings.json:5 [REDACTED]",
                "JWT_KEY appsettings.yaml:2 [REDACTED]",
                "GEMINI_API_KEY appsettings.yaml:4 [REDACTED]",
                *HISTORICAL_NOTICE.splitlines(),
            ],
            result.stdout.splitlines(),
        )
        for raw_secret in (json_jwt, json_gemini, yaml_jwt, yaml_gemini):
            self.assertNotIn(raw_secret, result.stdout)

    def test_tracks_structured_sections_across_braces_comments_and_direct_children(self) -> None:
        json_direct_jwt = "json-direct-jwt-secret-1234567890"  # secret-scan: test-fixture
        json_inline_gemini = "json-inline-gemini-secret"  # secret-scan: test-fixture
        yaml_direct_jwt = "yaml-comment-jwt-secret-1234567890"  # secret-scan: test-fixture
        self.track(
            "structured.json",
            "{\n"
            '  "Jwt":\n'
            "  {\n"
            '    "Metadata": {\n'
            '      "Key": "nested-metadata-key"\n'
            "    },\n"
            f'    "Key": "{json_direct_jwt}"\n'
            "  },\n"
            f'  "Gemini": {{ "Issuer": "earlier", "ApiKey": "{json_inline_gemini}" }}\n'
            "}\n",
        )
        self.track(
            "structured.yaml",
            "Jwt:\n"
            "# same-indent comment must not close the section\n"
            f"  Key: {yaml_direct_jwt}\n",
        )

        result = self.scan()

        self.assertNotEqual(0, result.returncode)
        self.assertEqual(
            [
                "JWT_KEY structured.json:7 [REDACTED]",
                "GEMINI_API_KEY structured.json:9 [REDACTED]",
                "JWT_KEY structured.yaml:3 [REDACTED]",
                *HISTORICAL_NOTICE.splitlines(),
            ],
            result.stdout.splitlines(),
        )
        for raw_secret in (json_direct_jwt, json_inline_gemini, yaml_direct_jwt):
            self.assertNotIn(raw_secret, result.stdout)

    def test_tracks_direct_keys_after_inline_section_properties(self) -> None:
        jwt = "inline-property-jwt-secret-1234567890"  # secret-scan: test-fixture
        gemini = "inline-property-gemini-secret"  # secret-scan: test-fixture
        self.track(
            "inline-properties.json",
            '{"Jwt": {"Issuer": "issuer",\n'
            f'  "Key": "{jwt}"\n'
            "},\n"
            '"Gemini": {"Model": "gemini-2.5-flash",\n'
            f'  "ApiKey": "{gemini}"\n'
            "}\n"
            "}\n",
        )

        result = self.scan()

        self.assertNotEqual(0, result.returncode)
        self.assertEqual(
            [
                "JWT_KEY inline-properties.json:2 [REDACTED]",
                "GEMINI_API_KEY inline-properties.json:5 [REDACTED]",
                *HISTORICAL_NOTICE.splitlines(),
            ],
            result.stdout.splitlines(),
        )
        for raw_secret in (jwt, gemini):
            self.assertNotIn(raw_secret, result.stdout)

    def test_tracks_sections_after_other_inline_json_properties(self) -> None:
        jwt = "other-property-jwt-secret-1234567890"  # secret-scan: test-fixture
        gemini = "other-property-gemini-secret"  # secret-scan: test-fixture
        self.track(
            "other-properties.json",
            '{"Other": true, "Jwt": {"Issuer": "issuer",\n'
            f'  "Key": "{jwt}"\n'
            "},\n"
            '"Other": true, "Gemini": {"Issuer": "issuer",\n'
            f'  "ApiKey": "{gemini}"\n'
            "}\n"
            "}\n",
        )

        result = self.scan()

        self.assertNotEqual(0, result.returncode)
        self.assertEqual(
            [
                "JWT_KEY other-properties.json:2 [REDACTED]",
                "GEMINI_API_KEY other-properties.json:5 [REDACTED]",
                *HISTORICAL_NOTICE.splitlines(),
            ],
            result.stdout.splitlines(),
        )
        for raw_secret in (jwt, gemini):
            self.assertNotIn(raw_secret, result.stdout)

    def test_tracks_multiple_open_sections_until_each_object_closes(self) -> None:
        jwt = "multi-section-jwt-secret-1234567890"  # secret-scan: test-fixture
        gemini = "multi-section-gemini-secret"  # secret-scan: test-fixture
        self.track(
            "multiple-sections.json",
            '{"Jwt": {"Gemini": {\n'
            f'  "ApiKey": "{gemini}"\n'
            "},\n"
            f'  "Key": "{jwt}"\n'
            "}}\n",
        )

        result = self.scan()

        self.assertNotEqual(0, result.returncode)
        self.assertEqual(
            [
                "GEMINI_API_KEY multiple-sections.json:2 [REDACTED]",
                "JWT_KEY multiple-sections.json:4 [REDACTED]",
                *HISTORICAL_NOTICE.splitlines(),
            ],
            result.stdout.splitlines(),
        )
        for raw_secret in (jwt, gemini):
            self.assertNotIn(raw_secret, result.stdout)

    def test_json_finds_later_direct_children_after_nested_objects(self) -> None:
        jwt = "later-direct-jwt-secret-1234567890"  # secret-scan: test-fixture
        gemini = "later-direct-gemini-secret"  # secret-scan: test-fixture
        self.track(
            "later-direct.json",
            "{\n"
            '  "Jwt": {"Issuer": "escaped \\"issuer\\"", "Metadata": {"Values": [1, {"Key": "nested"}]}, '
            f'"Key": "{jwt}"}},\n'
            '  "Gemini": {"Model": "flash", "Metadata": {"ApiKey": "nested"}, '
            f'"ApiKey": "{gemini}"}}\n'
            "}\n",
        )

        result = self.scan()

        self.assertNotEqual(0, result.returncode)
        self.assertEqual(
            [
                "JWT_KEY later-direct.json:2 [REDACTED]",
                "GEMINI_API_KEY later-direct.json:3 [REDACTED]",
                *HISTORICAL_NOTICE.splitlines(),
            ],
            result.stdout.splitlines(),
        )
        for raw_secret in (jwt, gemini):
            self.assertNotIn(raw_secret, result.stdout)

    def test_json_finds_pending_brace_objects_with_inline_keys(self) -> None:
        jwt = "pending-inline-jwt-secret-1234567890"  # secret-scan: test-fixture
        gemini = "pending-inline-gemini-secret"  # secret-scan: test-fixture
        self.track(
            "pending-inline.json",
            "{\n"
            '  "Jwt":\n'
            f'  {{ "Key": "{jwt}" }},\n'
            '  "Gemini":\n'
            f'  {{ "ApiKey": "{gemini}" }}\n'
            "}\n",
        )

        result = self.scan()

        self.assertNotEqual(0, result.returncode)
        self.assertEqual(
            [
                "JWT_KEY pending-inline.json:3 [REDACTED]",
                "GEMINI_API_KEY pending-inline.json:5 [REDACTED]",
                *HISTORICAL_NOTICE.splitlines(),
            ],
            result.stdout.splitlines(),
        )
        for raw_secret in (jwt, gemini):
            self.assertNotIn(raw_secret, result.stdout)

    def test_jsonc_handles_line_and_block_comments_around_section_headers(self) -> None:
        jwt = "jsonc-comment-jwt-secret-1234567890"  # secret-scan: test-fixture
        gemini = "jsonc-comment-gemini-secret"  # secret-scan: test-fixture
        self.track(
            "commented.jsonc",
            "{\n"
            '  "Jwt": /* signing configuration */ {\n'
            f'    "Key": "{jwt}"\n'
            "  },\n"
            '  "Gemini": // provider configuration\n'
            "  {\n"
            f'    "ApiKey": "{gemini}"\n'
            "  },\n"
            "}\n",
        )

        result = self.scan()

        self.assertNotEqual(0, result.returncode)
        self.assertEqual(
            [
                "JWT_KEY commented.jsonc:3 [REDACTED]",
                "GEMINI_API_KEY commented.jsonc:7 [REDACTED]",
                *HISTORICAL_NOTICE.splitlines(),
            ],
            result.stdout.splitlines(),
        )
        for raw_secret in (jwt, gemini):
            self.assertNotIn(raw_secret, result.stdout)

    def test_malformed_json_fails_closed_without_disclosing_values(self) -> None:
        missing = "malformed-missing-jwt-secret-1234567890"  # secret-scan: test-fixture
        duplicate = "malformed-comma-gemini-secret"  # secret-scan: test-fixture
        comment_jwt = "unterminated-comment-jwt-secret-1234567890"  # secret-scan: test-fixture
        comment_gemini = "unterminated-comment-gemini-secret"  # secret-scan: test-fixture
        self.track(
            "malformed-missing.json",
            "{\n"
            '  "Jwt": {\n'
            f'    "Key": "{missing}"\n',
        )
        self.track(
            "malformed-comma.json",
            "{\n"
            '  "Gemini": {\n'
            f'    "ApiKey": "{duplicate}",\n'
            "    ,\n"
            '    "Model": "flash"\n'
            "  }\n"
            "}\n",
        )
        self.track(
            "malformed-comment.jsonc",
            "{\n"
            "  /* unterminated comment\n"
            '  "Jwt": {\n'
            f'    "Key": "{comment_jwt}"\n'
            "  },\n"
            '  "Gemini": {\n'
            f'    "ApiKey": "{comment_gemini}"\n'
            "  }",
        )

        result = self.scan()

        self.assertNotEqual(0, result.returncode)
        self.assertEqual(
            [
                "SCAN_ERROR malformed-comma.json:4 [REDACTED]",
                "SCAN_ERROR malformed-comment.jsonc:8 [REDACTED]",
                "SCAN_ERROR malformed-missing.json:4 [REDACTED]",
                *HISTORICAL_NOTICE.splitlines(),
            ],
            result.stdout.splitlines(),
        )
        for raw_secret in (missing, duplicate, comment_jwt, comment_gemini):
            self.assertNotIn(raw_secret, result.stdout)

    def test_json_error_lines_handle_cr_and_crlf_newlines(self) -> None:
        for relative_path, newline in (
            ("malformed-cr.json", b"\r"),
            ("malformed-crlf.json", b"\r\n"),
        ):
            path = self.repo / relative_path
            path.write_bytes(
                newline.join(
                    (
                        b"{",
                        b'  \"Jwt\": {',
                        b'    \"Key\": \"line-ending-secret-1234567890\",',
                        b"    ,",
                        b"  }",
                        b"}",
                    )
                )
            )
            self.run_git("add", "--", relative_path)

        result = self.scan()

        self.assertNotEqual(0, result.returncode)
        self.assertEqual(
            [
                "SCAN_ERROR malformed-cr.json:4 [REDACTED]",
                "SCAN_ERROR malformed-crlf.json:4 [REDACTED]",
                *HISTORICAL_NOTICE.splitlines(),
            ],
            result.stdout.splitlines(),
        )
        self.assertNotIn("line-ending-secret", result.stdout)

    def test_yaml_flow_maps_detect_only_direct_section_keys(self) -> None:
        jwt = "yaml-flow-jwt-secret-1234567890"  # secret-scan: test-fixture
        gemini = "yaml-flow-gemini-secret"  # secret-scan: test-fixture
        self.track(
            "flow.yaml",
            f"Jwt: {{ Metadata: {{ Key: nested-jwt-value }}, Key: {jwt} }}\n"
            f'Gemini: {{ Metadata: {{ ApiKey: nested-gemini-value }}, ApiKey: "{gemini}" }}\n',
        )
        self.track(
            "nested-flow.yaml",
            "Jwt: { Metadata: { Key: nested-only-jwt-value } }\n"
            "Gemini: { Metadata: { ApiKey: nested-only-gemini-value } }\n",
        )

        result = self.scan()

        self.assertNotEqual(0, result.returncode)
        self.assertEqual(
            [
                "JWT_KEY flow.yaml:1 [REDACTED]",
                "GEMINI_API_KEY flow.yaml:2 [REDACTED]",
                *HISTORICAL_NOTICE.splitlines(),
            ],
            result.stdout.splitlines(),
        )
        for raw_secret in (jwt, gemini, "nested-jwt-value", "nested-gemini-value"):
            self.assertNotIn(raw_secret, result.stdout)

    def test_multiline_yaml_flow_maps_reject_placeholder_literal_suffixes(self) -> None:
        jwt = "${JWT_KEY} known-fallback"  # secret-scan: test-fixture
        gemini = "${{ secrets.GEMINI_KEY }} known-fallback"  # secret-scan: test-fixture
        self.track(
            "multiline-flow.yaml",
            "Jwt: {\n"
            "  Metadata: {\n"
            "    Key: nested-only-jwt-value\n"
            "  },\n"
            f"  Key: {jwt}\n"
            "}\n"
            "Gemini: {\n"
            "  Metadata: { ApiKey: nested-only-gemini-value },\n"
            f'  ApiKey: "{gemini}"\n'
            "}\n",
        )

        result = self.scan()

        self.assertNotEqual(0, result.returncode)
        self.assertEqual(
            [
                "JWT_KEY multiline-flow.yaml:5 [REDACTED]",
                "GEMINI_API_KEY multiline-flow.yaml:9 [REDACTED]",
                *HISTORICAL_NOTICE.splitlines(),
            ],
            result.stdout.splitlines(),
        )
        self.assertNotIn("known-fallback", result.stdout)

    def test_malformed_and_deep_yaml_flow_maps_fail_closed(self) -> None:
        malformed_jwt = "malformed-flow-jwt-secret-1234567890"  # secret-scan: test-fixture
        malformed_gemini = "malformed-flow-gemini-secret"  # secret-scan: test-fixture
        deep_jwt = "deep-flow-jwt-secret-1234567890"  # secret-scan: test-fixture
        deep_gemini = "deep-flow-gemini-secret"  # secret-scan: test-fixture
        depth = sys.getrecursionlimit() + 50
        self.track(
            "malformed-flow.yaml",
            f"Jwt: {{ Key: {malformed_jwt},\n"
            "  , Metadata: {} }\n"
            f"Gemini: {{ ApiKey: {malformed_gemini} }}\n",
        )
        self.track(
            "deep-flow.yaml",
            "Jwt: {"
            + " Metadata: {" * depth
            + f" Key: {deep_jwt}"
            + "}" * depth
            + f", Key: {deep_jwt} }}\n"
            + f"Gemini: {{ ApiKey: {deep_gemini} }}\n",
        )

        result = self.scan()

        self.assertNotEqual(0, result.returncode)
        self.assertEqual(
            [
                "SCAN_ERROR deep-flow.yaml:0 [REDACTED]",
                "SCAN_ERROR malformed-flow.yaml:2 [REDACTED]",
                *HISTORICAL_NOTICE.splitlines(),
            ],
            result.stdout.splitlines(),
        )
        for raw_secret in (malformed_jwt, malformed_gemini, deep_jwt, deep_gemini):
            self.assertNotIn(raw_secret, result.stdout)

    def test_yaml_hash_suffixes_are_literals_but_spaced_hashes_are_comments(self) -> None:
        shell_suffix = "${JWT_KEY}#literal-suffix"  # secret-scan: test-fixture
        github_suffix = "${{ secrets.GEMINI_KEY }}#literal-suffix"  # secret-scan: test-fixture
        self.track(
            "hash-flat.yaml",
            f"Jwt:Key={shell_suffix}\n"  # secret-scan: test-fixture
            f"Gemini:ApiKey={github_suffix}\n",  # secret-scan: test-fixture
        )
        self.track(
            "hash-block.yaml",
            "Jwt:\n"
            f"  Key: {shell_suffix}\n"
            "Gemini:\n"
            f"  ApiKey: {github_suffix}\n",
        )
        self.track(
            "hash-flow.yaml",
            f"Jwt: {{ Key: {shell_suffix} }}\n"
            f"Gemini: {{ ApiKey: {github_suffix} }}\n",
        )
        self.track(
            "hash-comments.yaml",
            "Jwt:\n"
            "  Key: ${JWT_KEY} # runtime placeholder\n"
            "Gemini:\n"
            "  ApiKey: ${{ secrets.GEMINI_KEY }} # runtime placeholder\n",
        )

        result = self.scan()

        self.assertNotEqual(0, result.returncode)
        self.assertEqual(
            [
                "JWT_KEY hash-block.yaml:2 [REDACTED]",
                "GEMINI_API_KEY hash-block.yaml:4 [REDACTED]",
                "JWT_KEY hash-flat.yaml:1 [REDACTED]",
                "GEMINI_API_KEY hash-flat.yaml:2 [REDACTED]",
                "JWT_KEY hash-flow.yaml:1 [REDACTED]",
                "GEMINI_API_KEY hash-flow.yaml:2 [REDACTED]",
                *HISTORICAL_NOTICE.splitlines(),
            ],
            result.stdout.splitlines(),
        )
        self.assertNotIn("literal-suffix", result.stdout)

    def test_whitespace_suffix_after_placeholder_is_detected_for_assignments_and_nested_key(self) -> None:
        password = "Password=${JWT_KEY} known-fallback"  # secret-scan: test-fixture
        jwt = "JWT__KEY=${{ secrets.JWT_KEY }} known-fallback"  # secret-scan: test-fixture
        gemini = "GEMINI__APIKEY=${GEMINI_KEY} known-fallback"  # secret-scan: test-fixture
        self.track("whitespace.env", f"{password}\n{jwt}\n{gemini}\n")
        self.track(
            "whitespace.json",
            f'{{ "Jwt": {{ "Key": "${{JWT_KEY}} known-fallback" }} }}\n',
        )

        result = self.scan()

        self.assertNotEqual(0, result.returncode)
        self.assertEqual(
            [
                "PASSWORD whitespace.env:1 [REDACTED]",
                "JWT_KEY whitespace.env:2 [REDACTED]",
                "GEMINI_API_KEY whitespace.env:3 [REDACTED]",
                "JWT_KEY whitespace.json:1 [REDACTED]",
                *HISTORICAL_NOTICE.splitlines(),
            ],
            result.stdout.splitlines(),
        )
        for raw_value in (password, jwt, gemini, "known-fallback"):
            self.assertNotIn(raw_value, result.stdout)

    def test_example_text_cannot_hide_high_entropy_test_credentials(self) -> None:
        uri = "postgresql://fixture:HighEntropyUriCredential123@db.example.invalid/calories"  # secret-scan: test-fixture
        password = "Password=HighEntropyPasswordCredential123 # example configuration"  # secret-scan: test-fixture
        self.track("tests/example_fixture.txt", f"{uri}\n{password}\n")

        result = self.scan()

        self.assertNotEqual(0, result.returncode)
        self.assertEqual(
            [
                "POSTGRES_URI_CREDENTIALS tests/example_fixture.txt:1 [REDACTED]",
                "PASSWORD tests/example_fixture.txt:2 [REDACTED]",
                *HISTORICAL_NOTICE.splitlines(),
            ],
            result.stdout.splitlines(),
        )
        self.assertNotIn("HighEntropyUriCredential123", result.stdout)
        self.assertNotIn("HighEntropyPasswordCredential123", result.stdout)

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

        self.assertEqual(0, result.returncode, result.stdout)

    def test_detects_all_required_categories_without_printing_values(self) -> None:
        findings = (
            ("GOOGLE_API_KEY", "google.txt", "AIzaSyCurrentSecret123456789012345678901"),  # secret-scan: test-fixture
            ("PRIVATE_KEY", "private.pem", "-----BEGIN PRIVATE KEY-----"),  # secret-scan: test-fixture
            ("POSTGRES_URI_CREDENTIALS", "database.txt", "postgresql://app:uri-secret@db/calories"),  # secret-scan: test-fixture
            ("JWT_KEY", "jwt.json", '{"Jwt:Key": "jwt-current-secret-value-1234567890"}'),  # secret-scan: test-fixture
            ("GEMINI_API_KEY", "gemini.json", '{"Gemini:ApiKey": "gemini-current-secret-value"}'),  # secret-scan: test-fixture
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
