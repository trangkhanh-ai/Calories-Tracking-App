#!/usr/bin/env python3
"""Scan Git's tracked files for current credentials without disclosing values."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import os
import re
import subprocess
import sys


FIXTURE_MARKER = "secret-scan: test-fixture"
HISTORICAL_NOTICES = (
    "Historical Gemini exposure: Yes",
    "Gemini key rotation required before production: Yes",
)

GOOGLE_API_KEY = re.compile(r"AIza[0-9A-Za-z_-]{20,}")
PRIVATE_KEY = re.compile(r"-----BEGIN (?:[A-Z0-9]+ )?PRIVATE KEY-----")
POSTGRES_URI = re.compile(
    r"postgres(?:ql)?://(?P<username>[^\s/:@]+):(?P<password>[^\s/@]+)@",
    re.IGNORECASE,
)
SHELL_PLACEHOLDER = r"\$\{[A-Za-z_][A-Za-z0-9_]*\}"
GITHUB_PLACEHOLDER = (
    r"\$\{\{\s*(?:secrets|env|vars)\.[A-Za-z_][A-Za-z0-9_]*\s*\}\}"
)
PLACEHOLDER_WITH_SUFFIX = (
    rf"(?:{GITHUB_PLACEHOLDER}|{SHELL_PLACEHOLDER})[ \t]+[^\s\"'#]+"
)
PASSWORD_PLACEHOLDER_WITH_SUFFIX = (
    rf"(?:{GITHUB_PLACEHOLDER}|{SHELL_PLACEHOLDER})[ \t]+[^\s;\"'#]+"
)
GITHUB_VALUE = GITHUB_PLACEHOLDER + r"[^\s\"']*"
PASSWORD_GITHUB_VALUE = GITHUB_PLACEHOLDER + r"[^\s;\"']*"
PLACEHOLDER_VALUE = PLACEHOLDER_WITH_SUFFIX + r"|" + GITHUB_VALUE + r"|[^\s\"']+"
PASSWORD_VALUE = (
    PASSWORD_PLACEHOLDER_WITH_SUFFIX
    + r"|"
    + PASSWORD_GITHUB_VALUE
    + r"|[^\s;\"']+"
)
JWT_KEY = re.compile(
    rf"(?:Jwt:Key|JWT__KEY)[\"']?\s*[:=]\s*[\"']?(?P<value>{PLACEHOLDER_VALUE})",
    re.IGNORECASE,
)
GEMINI_API_KEY = re.compile(
    rf"(?:Gemini:ApiKey|GEMINI__APIKEY)[\"']?\s*[:=]\s*[\"']?(?P<value>{PLACEHOLDER_VALUE})",
    re.IGNORECASE,
)
PASSWORD = re.compile(
    rf"\bPassword=\s*[\"']?(?P<value>{PASSWORD_VALUE})",
    re.IGNORECASE,
)
JWT_NESTED = re.compile(
    rf"[\"']?Jwt[\"']?\s*:\s*\{{[^\r\n{{}}]*?[\"']?Key[\"']?\s*:\s*[\"']?(?P<value>{PLACEHOLDER_VALUE})",
    re.IGNORECASE,
)
GEMINI_NESTED = re.compile(
    rf"[\"']?Gemini[\"']?\s*:\s*\{{[^\r\n{{}}]*?[\"']?ApiKey[\"']?\s*:\s*[\"']?(?P<value>{PLACEHOLDER_VALUE})",
    re.IGNORECASE,
)
EXPLICIT_PLACEHOLDER = re.compile(
    rf"(?:<[^<>\r\n]+>|{SHELL_PLACEHOLDER}|{GITHUB_PLACEHOLDER}|\.\.\.|redacted)",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class TrackedFile:
    mode: str
    path: str


@dataclass(frozen=True)
class Finding:
    category: str
    path: str
    line: int

    def render(self) -> str:
        return f"{self.category} {self.path}:{self.line} [REDACTED]"


@dataclass(frozen=True)
class JsonToken:
    kind: str
    value: str
    line: int


class JsonParseError(ValueError):
    def __init__(self, message: str, line: int) -> None:
        super().__init__(message)
        self.line = line


class YamlAstError(ValueError):
    def __init__(self, message: str, line: int) -> None:
        super().__init__(message)
        self.line = line


def tracked_files(repo: Path) -> list[TrackedFile]:
    result = subprocess.run(
        ["git", "ls-files", "--stage", "-z"],
        cwd=repo,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError("git ls-files failed")

    entries: list[TrackedFile] = []
    for raw_entry in result.stdout.split(b"\0"):
        if not raw_entry:
            continue
        metadata, separator, raw_path = raw_entry.partition(b"\t")
        if not separator:
            raise RuntimeError("unexpected git ls-files output")
        fields = metadata.split()
        if len(fields) != 3:
            raise RuntimeError("unexpected git ls-files metadata")
        mode = fields[0].decode("ascii")
        stage = fields[2].decode("ascii")
        if stage != "0":
            raise RuntimeError("unmerged index entry")
        path = raw_path.decode(sys.getfilesystemencoding(), errors="surrogateescape")
        entries.append(TrackedFile(mode=mode, path=path))
    return entries


def is_placeholder(value: str) -> bool:
    candidate = value.strip().strip("\"'").rstrip(",")
    if not candidate:
        return True
    return EXPLICIT_PLACEHOLDER.fullmatch(candidate) is not None


def is_test_fixture_path(path: str) -> bool:
    return bool({"test", "tests", "fixture", "fixtures"} & {part.lower() for part in Path(path).parts})


def is_obvious_test_fixture(path: str, value: str) -> bool:
    if not is_test_fixture_path(path):
        return False
    return value.strip().strip("\"'").lower() in {
        "test",
        "secret",
        "password",
        "p%40ssword",
        "p%40ss%3aword",
    }


def tokenize_jsonc(text: str) -> list[JsonToken]:
    tokens: list[JsonToken] = []
    index = 0
    line = 1
    length = len(text)
    escape_values = {
        '"': '"',
        "\\": "\\",
        "/": "/",
        "b": "\b",
        "f": "\f",
        "n": "\n",
        "r": "\r",
        "t": "\t",
    }

    while index < length:
        character = text[index]
        if character == "\ufeff" and index == 0:
            index += 1
            continue
        if character.isspace():
            if character == "\r":
                line += 1
                index += 2 if index + 1 < length and text[index + 1] == "\n" else 1
                continue
            if character == "\n":
                line += 1
            index += 1
            continue
        if text.startswith("//", index):
            index += 2
            while index < length and text[index] not in "\r\n":
                index += 1
            continue
        if text.startswith("/*", index):
            index += 2
            while index < length and not text.startswith("*/", index):
                if text[index] == "\r":
                    line += 1
                    index += (
                        2 if index + 1 < length and text[index + 1] == "\n" else 1
                    )
                    continue
                if text[index] == "\n":
                    line += 1
                index += 1
            if index >= length:
                raise JsonParseError("unterminated block comment", line)
            index += 2
            continue
        if character in "{}[]:,":
            tokens.append(JsonToken(character, character, line))
            index += 1
            continue
        if character == '"':
            token_line = line
            index += 1
            value: list[str] = []
            while index < length:
                character = text[index]
                if character == '"':
                    index += 1
                    tokens.append(JsonToken("string", "".join(value), token_line))
                    break
                if character in "\r\n" or ord(character) < 0x20:
                    raise JsonParseError("invalid string character", line)
                if character != "\\":
                    value.append(character)
                    index += 1
                    continue

                index += 1
                if index >= length:
                    raise JsonParseError("unterminated string escape", line)
                escape = text[index]
                if escape != "u":
                    if escape not in escape_values:
                        raise JsonParseError("invalid string escape", line)
                    value.append(escape_values[escape])
                    index += 1
                    continue

                hexadecimal = text[index + 1 : index + 5]
                if len(hexadecimal) != 4 or not all(
                    digit in "0123456789abcdefABCDEF" for digit in hexadecimal
                ):
                    raise JsonParseError("invalid unicode escape", line)
                codepoint = int(hexadecimal, 16)
                index += 5
                if 0xD800 <= codepoint <= 0xDBFF and text.startswith("\\u", index):
                    low_hexadecimal = text[index + 2 : index + 6]
                    if len(low_hexadecimal) == 4 and all(
                        digit in "0123456789abcdefABCDEF" for digit in low_hexadecimal
                    ):
                        low_codepoint = int(low_hexadecimal, 16)
                        if 0xDC00 <= low_codepoint <= 0xDFFF:
                            codepoint = (
                                0x10000
                                + ((codepoint - 0xD800) << 10)
                                + (low_codepoint - 0xDC00)
                            )
                            index += 6
                value.append(chr(codepoint))
            else:
                raise JsonParseError("unterminated string", line)
            continue

        token_line = line
        start = index
        while index < length:
            character = text[index]
            if character.isspace() or character in "{}[]:,":
                break
            if text.startswith("//", index) or text.startswith("/*", index):
                break
            index += 1
        if start == index:
            raise JsonParseError("unexpected character", line)
        tokens.append(JsonToken("scalar", text[start:index], token_line))

    tokens.append(JsonToken("eof", "", line))
    return tokens


class JsonSecretParser:
    def __init__(self, path: str, text: str) -> None:
        self.path = path
        self.lines = text.splitlines()
        self.tokens = tokenize_jsonc(text)
        self.index = 0
        self.findings: list[Finding] = []
        self.seen_findings: set[tuple[str, int]] = set()

    def parse(self) -> list[Finding]:
        self._parse_value(None)
        self._expect("eof")
        return self.findings

    def _peek(self) -> JsonToken:
        return self.tokens[self.index]

    def _advance(self) -> JsonToken:
        token = self._peek()
        self.index += 1
        return token

    def _accept(self, kind: str) -> bool:
        if self._peek().kind != kind:
            return False
        self._advance()
        return True

    def _expect(self, kind: str) -> JsonToken:
        token = self._advance()
        if token.kind != kind:
            raise JsonParseError(f"expected {kind}", token.line)
        return token

    def _parse_value(self, section: str | None) -> None:
        token = self._peek()
        if token.kind == "{":
            self._parse_object(section)
        elif token.kind == "[":
            self._parse_array()
        elif token.kind in {"string", "scalar"}:
            self._advance()
        else:
            raise JsonParseError("expected value", token.line)

    def _parse_object(self, section: str | None) -> None:
        self._expect("{")
        if self._accept("}"):
            return

        while True:
            property_token = self._expect("string")
            self._expect(":")
            value_token = self._peek()
            property_name = property_token.value.lower()
            category = None
            if section == "jwt" and property_name == "key":
                category = "JWT_KEY"
            elif section == "gemini" and property_name == "apikey":
                category = "GEMINI_API_KEY"
            if category and value_token.kind in {"string", "scalar"}:
                self._record_finding(category, value_token)

            child_section = property_name if property_name in {"jwt", "gemini"} else None
            self._parse_value(child_section)
            if self._accept(","):
                if self._accept("}"):
                    return
                continue
            self._expect("}")
            return

    def _parse_array(self) -> None:
        self._expect("[")
        if self._accept("]"):
            return
        while True:
            self._parse_value(None)
            if self._accept(","):
                if self._accept("]"):
                    return
                continue
            self._expect("]")
            return

    def _record_finding(self, category: str, token: JsonToken) -> None:
        if is_placeholder(token.value) or is_obvious_test_fixture(self.path, token.value):
            return
        source_line = self.lines[token.line - 1] if token.line <= len(self.lines) else ""
        if FIXTURE_MARKER in source_line.lower() and is_test_fixture_path(self.path):
            return
        finding_key = (category, token.line)
        if finding_key not in self.seen_findings:
            self.findings.append(Finding(category, self.path, token.line))
            self.seen_findings.add(finding_key)


def scan_json_secrets(path: str, text: str) -> tuple[list[Finding], int | None]:
    try:
        return JsonSecretParser(path, text).parse(), None
    except JsonParseError as error:
        return [], error.line
    except RecursionError:
        return [], 0


def generic_secret_categories(
    path: str,
    text: str,
    include_assignments: bool = True,
    include_inline_sections: bool = True,
) -> list[str]:
    categories: list[str] = []
    found_categories: set[str] = set()

    def add_category(category: str) -> None:
        if category not in found_categories:
            categories.append(category)
            found_categories.add(category)

    def has_literal_match(pattern: re.Pattern[str]) -> bool:
        return any(
            not (
                is_placeholder(match.group("value"))
                or is_obvious_test_fixture(path, match.group("value"))
            )
            for match in pattern.finditer(text)
        )

    if GOOGLE_API_KEY.search(text):
        add_category("GOOGLE_API_KEY")
    if PRIVATE_KEY.search(text):
        add_category("PRIVATE_KEY")
    if any(
        not (
            is_placeholder(match.group("username"))
            or is_placeholder(match.group("password"))
            or is_obvious_test_fixture(path, match.group("password"))
        )
        for match in POSTGRES_URI.finditer(text)
    ):
        add_category("POSTGRES_URI_CREDENTIALS")

    if include_assignments:
        for category, pattern in (
            ("JWT_KEY", JWT_KEY),
            ("GEMINI_API_KEY", GEMINI_API_KEY),
            ("PASSWORD", PASSWORD),
        ):
            if has_literal_match(pattern):
                add_category(category)

    if include_inline_sections:
        if has_literal_match(JWT_NESTED):
            add_category("JWT_KEY")
        if has_literal_match(GEMINI_NESTED):
            add_category("GEMINI_API_KEY")
    return categories


def scan_yaml_secrets(path: str, text: str) -> tuple[list[Finding], int | None]:
    try:
        import yaml
        from yaml.nodes import MappingNode, ScalarNode, SequenceNode
    except Exception:
        return [], 0

    def mark_line(mark: object | None) -> int:
        raw_line = getattr(mark, "line", None)
        return raw_line + 1 if isinstance(raw_line, int) and raw_line >= 0 else 0

    try:
        documents = list(yaml.compose_all(text, Loader=yaml.SafeLoader))
    except yaml.YAMLError as error:
        mark = getattr(error, "problem_mark", None) or getattr(
            error, "context_mark", None
        )
        return [], mark_line(mark)
    except Exception:
        return [], 0

    if not any(document is not None for document in documents):
        return [], None

    findings: list[Finding] = []
    seen_findings: set[tuple[str, int]] = set()
    source_lines = text.splitlines()
    visited: set[int] = set()
    merge_tag = "tag:yaml.org,2002:merge"

    def effective_mapping_items(
        node: object,
        resolving: set[int] | None = None,
    ) -> list[tuple[object, object]]:
        if not isinstance(node, MappingNode):
            return []

        active = resolving if resolving is not None else set()
        node_id = id(node)
        if node_id in active:
            raise YamlAstError("recursive YAML merge", mark_line(node.start_mark))
        active.add(node_id)
        try:
            merged: dict[str, tuple[object, object]] = {}
            explicit: dict[str, tuple[object, object]] = {}
            for key_node, value_node in node.value:
                if isinstance(key_node, ScalarNode) and key_node.tag == merge_tag:
                    if isinstance(value_node, MappingNode):
                        merge_sources = [value_node]
                    elif isinstance(value_node, SequenceNode) and all(
                        isinstance(item, MappingNode) for item in value_node.value
                    ):
                        merge_sources = value_node.value
                    else:
                        raise YamlAstError(
                            "invalid YAML merge", mark_line(value_node.start_mark)
                        )
                    for source in merge_sources:
                        for merged_key, merged_value in effective_mapping_items(
                            source, active
                        ):
                            if isinstance(merged_key, ScalarNode):
                                merged.setdefault(
                                    merged_key.value, (merged_key, merged_value)
                                )
                    continue
                if isinstance(key_node, ScalarNode):
                    explicit[key_node.value] = (key_node, value_node)
            merged.update(explicit)
            return list(merged.values())
        finally:
            active.remove(node_id)

    def add_finding(category: str, line: int) -> None:
        source_line = source_lines[line - 1] if 0 < line <= len(source_lines) else ""
        if FIXTURE_MARKER in source_line.lower() and is_test_fixture_path(path):
            return
        finding_key = (category, line)
        if finding_key not in seen_findings:
            findings.append(Finding(category, path, line))
            seen_findings.add(finding_key)

    def record_finding(category: str, value_node: object) -> None:
        if not isinstance(value_node, ScalarNode):
            return
        value = value_node.value
        if is_placeholder(value) or is_obvious_test_fixture(path, value):
            return
        add_finding(category, mark_line(value_node.start_mark))

    def scan_generic_text(candidate: str, line: int) -> None:
        for category in generic_secret_categories(
            path, candidate, include_inline_sections=False
        ):
            add_finding(category, line)

    def scan_scalar(node: object, mapping_key: str | None = None) -> None:
        if not isinstance(node, ScalarNode):
            return
        if node.style in {"|", ">"}:
            first_content_index = mark_line(node.start_mark)
            end_index = getattr(node.end_mark, "line", len(source_lines))
            if not isinstance(end_index, int):
                end_index = len(source_lines)
            for source_index in range(
                first_content_index, min(end_index, len(source_lines))
            ):
                content_line = source_lines[source_index]
                scan_generic_text(content_line, source_index + 1)
                if mapping_key is not None:
                    scan_generic_text(
                        f"{mapping_key}={content_line.strip()}", source_index + 1
                    )
            return

        line = mark_line(node.start_mark)
        scan_generic_text(node.value, line)
        if mapping_key is not None:
            scan_generic_text(f"{mapping_key}={node.value}", line)

    def visit(node: object) -> None:
        node_id = id(node)
        if node_id in visited:
            return
        visited.add(node_id)

        if isinstance(node, MappingNode):
            items = effective_mapping_items(node)
            for key_node, value_node in items:
                if not isinstance(key_node, ScalarNode) or not isinstance(
                    value_node, MappingNode
                ):
                    continue
                section = key_node.value.casefold()
                if section not in {"jwt", "gemini"}:
                    continue
                target_key = "key" if section == "jwt" else "apikey"
                category = "JWT_KEY" if section == "jwt" else "GEMINI_API_KEY"
                for child_key, child_value in effective_mapping_items(value_node):
                    if (
                        isinstance(child_key, ScalarNode)
                        and child_key.value.casefold() == target_key
                    ):
                        record_finding(category, child_value)
            for key_node, value_node in items:
                scan_scalar(key_node)
                mapping_key = (
                    key_node.value if isinstance(key_node, ScalarNode) else None
                )
                scan_scalar(value_node, mapping_key)
                if not isinstance(value_node, ScalarNode):
                    visit(value_node)
        elif isinstance(node, SequenceNode):
            for value_node in node.value:
                visit(value_node)
        elif isinstance(node, ScalarNode):
            scan_scalar(node)

    try:
        for document in documents:
            if document is not None:
                visit(document)
    except YamlAstError as error:
        return [], error.line
    except RecursionError:
        return [], 0
    except Exception:
        return [], 0
    return findings, None


def scan_line(
    path: str,
    line_number: int,
    line: str,
    include_assignments: bool = True,
    include_inline_sections: bool = True,
) -> list[Finding]:
    if FIXTURE_MARKER in line.lower() and is_test_fixture_path(path):
        return []
    return [
        Finding(category, path, line_number)
        for category in generic_secret_categories(
            path,
            line,
            include_assignments=include_assignments,
            include_inline_sections=include_inline_sections,
        )
    ]


def scan(repo: Path) -> list[Finding]:
    findings: list[Finding] = []
    seen_paths: set[str] = set()
    for entry in tracked_files(repo):
        if entry.path in seen_paths:
            continue
        seen_paths.add(entry.path)

        candidate = repo / entry.path
        if entry.mode == "120000" or candidate.is_symlink():
            findings.append(Finding("TRACKED_SYMLINK", entry.path, 0))
            continue
        if entry.mode == "160000" or not candidate.exists():
            continue

        try:
            content = candidate.read_bytes()
        except OSError:
            findings.append(Finding("SCAN_ERROR", entry.path, 0))
            continue
        if b"\0" in content:
            continue

        text = content.decode("utf-8", errors="replace")
        suffix = candidate.suffix.lower()
        is_json = suffix in {".json", ".jsonc"}
        is_yaml = suffix in {".yaml", ".yml"}
        parsed_json_findings: list[Finding] = []
        json_error_line: int | None = None
        if is_json:
            parsed_json_findings, json_error_line = scan_json_secrets(entry.path, text)
            if json_error_line is not None:
                findings.append(Finding("SCAN_ERROR", entry.path, json_error_line))
        structured_findings_by_line: dict[int, list[Finding]] = {}
        for finding in parsed_json_findings:
            structured_findings_by_line.setdefault(finding.line, []).append(finding)
        if is_yaml:
            parsed_yaml_findings, yaml_error_line = scan_yaml_secrets(entry.path, text)
            if yaml_error_line is not None:
                findings.append(Finding("SCAN_ERROR", entry.path, yaml_error_line))
                continue
            for finding in parsed_yaml_findings:
                structured_findings_by_line.setdefault(finding.line, []).append(finding)

        for line_number, line in enumerate(text.splitlines(), start=1):
            line_findings = (
                []
                if is_yaml
                else scan_line(
                    entry.path,
                    line_number,
                    line,
                    include_inline_sections=not is_json,
                )
            )
            findings.extend(line_findings)
            found_categories = {finding.category for finding in line_findings}
            for finding in structured_findings_by_line.get(line_number, []):
                if finding.category not in found_categories:
                    findings.append(finding)
    return findings


def main() -> int:
    try:
        findings = scan(Path.cwd())
    except RuntimeError:
        findings = [Finding("SCAN_ERROR", ".", 0)]

    for finding in findings:
        print(finding.render())
    for notice in HISTORICAL_NOTICES:
        print(notice)
    return 1 if findings else 0


if __name__ == "__main__":
    raise SystemExit(main())
