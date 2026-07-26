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
GITHUB_VALUE = GITHUB_PLACEHOLDER + r"[^\s\"'#]*"
PASSWORD_GITHUB_VALUE = GITHUB_PLACEHOLDER + r"[^\s;\"'#]*"
PLACEHOLDER_VALUE = PLACEHOLDER_WITH_SUFFIX + r"|" + GITHUB_VALUE + r"|[^\s\"'#]+"
YAML_GITHUB_VALUE = GITHUB_PLACEHOLDER + r"[^\s\"']*"
YAML_VALUE = PLACEHOLDER_WITH_SUFFIX + r"|" + YAML_GITHUB_VALUE + r"|[^\s\"']+"
PASSWORD_VALUE = (
    PASSWORD_PLACEHOLDER_WITH_SUFFIX
    + r"|"
    + PASSWORD_GITHUB_VALUE
    + r"|[^\s;\"'#]+"
)
JWT_KEY = re.compile(
    rf"(?:Jwt:Key|JWT__KEY)[\"']?\s*[:=]\s*[\"']?(?P<value>{PLACEHOLDER_VALUE})",
    re.IGNORECASE,
)
GEMINI_API_KEY = re.compile(
    rf"(?:Gemini:ApiKey|GEMINI__APIKEY)[\"']?\s*[:=]\s*[\"']?(?P<value>{PLACEHOLDER_VALUE})",
    re.IGNORECASE,
)
YAML_JWT_KEY = re.compile(
    rf"(?:Jwt:Key|JWT__KEY)[\"']?\s*[:=]\s*[\"']?(?P<value>{YAML_VALUE})",
    re.IGNORECASE,
)
YAML_GEMINI_API_KEY = re.compile(
    rf"(?:Gemini:ApiKey|GEMINI__APIKEY)[\"']?\s*[:=]\s*[\"']?(?P<value>{YAML_VALUE})",
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
YAML_JWT_NESTED = re.compile(
    rf"[\"']?Jwt[\"']?\s*:\s*\{{[^\r\n{{}}]*?[\"']?Key[\"']?\s*:\s*[\"']?(?P<value>{YAML_VALUE})",
    re.IGNORECASE,
)
YAML_GEMINI_NESTED = re.compile(
    rf"[\"']?Gemini[\"']?\s*:\s*\{{[^\r\n{{}}]*?[\"']?ApiKey[\"']?\s*:\s*[\"']?(?P<value>{YAML_VALUE})",
    re.IGNORECASE,
)
JWT_CHILD = re.compile(
    rf"^\s*[\"']?Key[\"']?\s*:\s*[\"']?(?P<value>{PLACEHOLDER_VALUE})",
    re.IGNORECASE,
)
GEMINI_CHILD = re.compile(
    rf"^\s*[\"']?ApiKey[\"']?\s*:\s*[\"']?(?P<value>{PLACEHOLDER_VALUE})",
    re.IGNORECASE,
)
YAML_JWT_CHILD = re.compile(
    rf"^\s*[\"']?Key[\"']?\s*:\s*[\"']?(?P<value>{YAML_VALUE})",
    re.IGNORECASE,
)
YAML_GEMINI_CHILD = re.compile(
    rf"^\s*[\"']?ApiKey[\"']?\s*:\s*[\"']?(?P<value>{YAML_VALUE})",
    re.IGNORECASE,
)
YAML_SECTION_HEADER = re.compile(
    r"^(?P<indent>\s*)[\"']?(?P<section>Jwt|Gemini)[\"']?\s*:\s*(?:#.*)?$",
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


@dataclass(frozen=True)
class YamlFlowToken:
    kind: str
    value: str
    line: int


@dataclass
class YamlSectionState:
    section: str
    indent: int
    direct_child_indent: int | None = None


class JsonParseError(ValueError):
    def __init__(self, message: str, line: int) -> None:
        super().__init__(message)
        self.line = line


class YamlFlowParseError(ValueError):
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


def tokenize_yaml_flow(text: str) -> list[YamlFlowToken]:
    tokens: list[YamlFlowToken] = []
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
        if character.isspace():
            if character == "\n":
                line += 1
            index += 1
            continue
        if character == "#" and (index == 0 or text[index - 1].isspace()):
            while index < length and text[index] not in "\r\n":
                index += 1
            continue
        if text.startswith("${{", index):
            placeholder_end = text.find("}}", index + 3)
            if placeholder_end != -1:
                tokens.append(
                    YamlFlowToken("scalar", text[index : placeholder_end + 2], line)
                )
                index = placeholder_end + 2
                continue
        if text.startswith("${", index):
            placeholder_end = text.find("}", index + 2)
            if placeholder_end != -1:
                tokens.append(
                    YamlFlowToken("scalar", text[index : placeholder_end + 1], line)
                )
                index = placeholder_end + 1
                continue
        if character in "{}[]:,":
            tokens.append(YamlFlowToken(character, character, line))
            index += 1
            continue
        if character == "'":
            token_line = line
            index += 1
            value: list[str] = []
            while index < length:
                character = text[index]
                if character == "'":
                    if index + 1 < length and text[index + 1] == "'":
                        value.append("'")
                        index += 2
                        continue
                    index += 1
                    tokens.append(YamlFlowToken("scalar", "".join(value), token_line))
                    break
                if character == "\n":
                    line += 1
                value.append(character)
                index += 1
            else:
                raise YamlFlowParseError("unterminated single-quoted scalar", line)
            continue
        if character == '"':
            token_line = line
            index += 1
            value = []
            while index < length:
                character = text[index]
                if character == '"':
                    index += 1
                    tokens.append(YamlFlowToken("scalar", "".join(value), token_line))
                    break
                if character == "\n":
                    line += 1
                if character != "\\":
                    value.append(character)
                    index += 1
                    continue
                index += 1
                if index >= length:
                    raise YamlFlowParseError("unterminated double-quoted escape", line)
                escape = text[index]
                value.append(escape_values.get(escape, escape))
                index += 1
            else:
                raise YamlFlowParseError("unterminated double-quoted scalar", line)
            continue

        token_line = line
        start = index
        while index < length:
            character = text[index]
            if character.isspace() or character in "{}[]:,":
                break
            index += 1
        tokens.append(YamlFlowToken("scalar", text[start:index], token_line))

    tokens.append(YamlFlowToken("eof", "", line))
    return tokens


class YamlFlowSecretParser:
    def __init__(self, path: str, text: str) -> None:
        self.path = path
        self.lines = text.splitlines()
        self.tokens = tokenize_yaml_flow(text)
        self.findings: list[Finding] = []
        self.seen_findings: set[tuple[str, int]] = set()

    def parse(self) -> list[Finding]:
        for index in range(len(self.tokens) - 2):
            token = self.tokens[index]
            section = token.value.lower()
            if (
                token.kind == "scalar"
                and section in {"jwt", "gemini"}
                and self.tokens[index + 1].kind == ":"
                and self.tokens[index + 2].kind == "{"
            ):
                self._parse_mapping(index + 2, section)
        return self.findings

    def _token(self, index: int) -> YamlFlowToken:
        if index >= len(self.tokens):
            raise YamlFlowParseError("unexpected end of flow mapping", self.tokens[-1].line)
        return self.tokens[index]

    def _parse_mapping(self, index: int, section: str | None) -> int:
        index = self._expect(index, "{")
        if self._token(index).kind == "}":
            return index + 1

        while True:
            property_token = self._token(index)
            if property_token.kind != "scalar":
                raise YamlFlowParseError("expected flow property", property_token.line)
            index = self._expect(index + 1, ":")
            property_name = property_token.value.lower()
            category = None
            if section == "jwt" and property_name == "key":
                category = "JWT_KEY"
            elif section == "gemini" and property_name == "apikey":
                category = "GEMINI_API_KEY"

            child_section = property_name if property_name in {"jwt", "gemini"} else None
            if self._token(index).kind in {"{", "["}:
                index = self._parse_value(index, child_section)
            else:
                index, scalar_value, scalar_line = self._parse_scalar(index, {",", "}"})
                if category:
                    self._record_finding(category, scalar_value, scalar_line)

            token = self._token(index)
            if token.kind == ",":
                index += 1
                if self._token(index).kind == "}":
                    return index + 1
                continue
            if token.kind != "}":
                raise YamlFlowParseError("expected flow mapping close", token.line)
            return index + 1

    def _parse_sequence(self, index: int) -> int:
        index = self._expect(index, "[")
        if self._token(index).kind == "]":
            return index + 1
        while True:
            index = self._parse_value(index, None)
            token = self._token(index)
            if token.kind == ",":
                index += 1
                if self._token(index).kind == "]":
                    return index + 1
                continue
            if token.kind != "]":
                raise YamlFlowParseError("expected flow sequence close", token.line)
            return index + 1

    def _parse_value(self, index: int, section: str | None) -> int:
        if self._token(index).kind == "{":
            return self._parse_mapping(index, section)
        if self._token(index).kind == "[":
            return self._parse_sequence(index)
        index, _, _ = self._parse_scalar(index, {",", "}", "]"})
        return index

    def _parse_scalar(
        self,
        index: int,
        terminators: set[str],
    ) -> tuple[int, str, int]:
        scalar_line = self._token(index).line
        values: list[str] = []
        while self._token(index).kind not in terminators | {"eof"}:
            values.append(self._token(index).value)
            index += 1
        if not values:
            raise YamlFlowParseError("expected flow scalar", scalar_line)
        return index, " ".join(values), scalar_line

    def _expect(self, index: int, kind: str) -> int:
        token = self._token(index)
        if token.kind != kind:
            raise YamlFlowParseError(f"expected {kind}", token.line)
        return index + 1

    def _record_finding(self, category: str, value: str, line: int) -> None:
        if is_placeholder(value) or is_obvious_test_fixture(self.path, value):
            return
        source_line = self.lines[line - 1] if line <= len(self.lines) else ""
        if FIXTURE_MARKER in source_line.lower() and is_test_fixture_path(self.path):
            return
        finding_key = (category, line)
        if finding_key not in self.seen_findings:
            self.findings.append(Finding(category, self.path, line))
            self.seen_findings.add(finding_key)


def scan_yaml_flow_secrets(path: str, text: str) -> tuple[list[Finding], int | None]:
    try:
        return YamlFlowSecretParser(path, text).parse(), None
    except YamlFlowParseError as error:
        return [], error.line
    except RecursionError:
        return [], 0


def scan_line(
    path: str,
    line_number: int,
    line: str,
    direct_sections: set[str] | None = None,
    include_inline_sections: bool = True,
) -> list[Finding]:
    if FIXTURE_MARKER in line.lower() and is_test_fixture_path(path):
        return []

    findings: list[Finding] = []
    found_categories: set[str] = set()
    is_yaml = Path(path).suffix.lower() in {".yaml", ".yml"}

    def add_finding(category: str) -> None:
        if category not in found_categories:
            findings.append(Finding(category, path, line_number))
            found_categories.add(category)

    def has_literal_match(pattern: re.Pattern[str]) -> bool:
        return any(
            not (
                is_placeholder(match.group("value"))
                or is_obvious_test_fixture(path, match.group("value"))
            )
            for match in pattern.finditer(line)
        )

    if GOOGLE_API_KEY.search(line):
        add_finding("GOOGLE_API_KEY")
    if PRIVATE_KEY.search(line):
        add_finding("PRIVATE_KEY")

    if any(
        not (
            is_placeholder(match.group("username"))
            or is_placeholder(match.group("password"))
            or is_obvious_test_fixture(path, match.group("password"))
        )
        for match in POSTGRES_URI.finditer(line)
    ):
        add_finding("POSTGRES_URI_CREDENTIALS")

    for category, pattern in (
        ("JWT_KEY", YAML_JWT_KEY if is_yaml else JWT_KEY),
        ("GEMINI_API_KEY", YAML_GEMINI_API_KEY if is_yaml else GEMINI_API_KEY),
        ("PASSWORD", PASSWORD),
    ):
        if has_literal_match(pattern):
            add_finding(category)

    if include_inline_sections:
        if has_literal_match(YAML_JWT_NESTED if is_yaml else JWT_NESTED):
            add_finding("JWT_KEY")
        if has_literal_match(YAML_GEMINI_NESTED if is_yaml else GEMINI_NESTED):
            add_finding("GEMINI_API_KEY")

    active_direct_sections = direct_sections or set()
    jwt_child = YAML_JWT_CHILD if is_yaml else JWT_CHILD
    gemini_child = YAML_GEMINI_CHILD if is_yaml else GEMINI_CHILD
    if "jwt" in active_direct_sections and has_literal_match(jwt_child):
        add_finding("JWT_KEY")
    if "gemini" in active_direct_sections and has_literal_match(gemini_child):
        add_finding("GEMINI_API_KEY")
    return findings


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
        parsed_json_findings: list[Finding] = []
        json_error_line: int | None = None
        yaml_error_line: int | None = None
        if is_json:
            parsed_json_findings, json_error_line = scan_json_secrets(entry.path, text)
            if json_error_line is not None:
                findings.append(Finding("SCAN_ERROR", entry.path, json_error_line))
        structured_findings_by_line: dict[int, list[Finding]] = {}
        for finding in parsed_json_findings:
            structured_findings_by_line.setdefault(finding.line, []).append(finding)
        if suffix in {".yaml", ".yml"}:
            parsed_yaml_findings, yaml_error_line = scan_yaml_flow_secrets(
                entry.path, text
            )
            if yaml_error_line is not None:
                findings.append(Finding("SCAN_ERROR", entry.path, yaml_error_line))
            for finding in parsed_yaml_findings:
                structured_findings_by_line.setdefault(finding.line, []).append(finding)

        yaml_sections: list[YamlSectionState] = []
        for line_number, line in enumerate(text.splitlines(), start=1):
            stripped = line.strip()
            indentation = len(line) - len(line.lstrip())

            direct_sections: set[str] = set()
            if suffix in {".yaml", ".yml"}:
                is_yaml_content = bool(stripped) and not stripped.startswith("#")
                if is_yaml_content:
                    yaml_sections = [
                        state for state in yaml_sections if indentation > state.indent
                    ]
                    for state in yaml_sections:
                        if state.direct_child_indent is None:
                            state.direct_child_indent = indentation
                        if indentation == state.direct_child_indent:
                            direct_sections.add(state.section)
                    header_match = YAML_SECTION_HEADER.match(line)
                    if header_match:
                        yaml_sections.append(
                            YamlSectionState(
                                section=header_match.group("section").lower(),
                                indent=len(header_match.group("indent")),
                            )
                        )

            line_findings = scan_line(
                entry.path,
                line_number,
                line,
                direct_sections,
                include_inline_sections=not is_json and yaml_error_line is None,
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
