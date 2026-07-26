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
JWT_CHILD = re.compile(
    rf"^\s*[\"']?Key[\"']?\s*:\s*[\"']?(?P<value>{PLACEHOLDER_VALUE})",
    re.IGNORECASE,
)
GEMINI_CHILD = re.compile(
    rf"^\s*[\"']?ApiKey[\"']?\s*:\s*[\"']?(?P<value>{PLACEHOLDER_VALUE})",
    re.IGNORECASE,
)
SECTION_HEADER = re.compile(
    r"^(?P<indent>\s*)[\"']?(?P<section>Jwt|Gemini)[\"']?\s*:\s*(?:\{\s*)?(?:#.*)?$",
    re.IGNORECASE,
)
SECTION_OBJECT_START = re.compile(
    r"[\"']?(?P<section>Jwt|Gemini)[\"']?\s*:\s*\{",
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


def structural_brace_counts(line: str) -> tuple[int, int]:
    """Count object braces while ignoring quoted values and placeholders."""
    opening = 0
    closing = 0
    quote: str | None = None
    escaped = False
    index = 0
    while index < len(line):
        character = line[index]
        if quote:
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == quote:
                quote = None
            index += 1
            continue

        if character in "\"'":
            quote = character
            index += 1
            continue
        if character == "#" or line.startswith("//", index):
            break
        if line.startswith("${{", index):
            placeholder_end = line.find("}}", index + 3)
            if placeholder_end != -1:
                index = placeholder_end + 2
                continue
        if line.startswith("${", index):
            placeholder_end = line.find("}", index + 2)
            if placeholder_end != -1:
                index = placeholder_end + 1
                continue
        if character == "{":
            opening += 1
        elif character == "}":
            closing += 1
        index += 1
    return opening, closing


def find_section_object_start(line: str, brace_depth: int) -> tuple[str, int] | None:
    """Find the last unquoted Jwt/Gemini object start and its absolute depth."""
    quote: str | None = None
    escaped = False
    current_depth = brace_depth
    section_start: tuple[str, int] | None = None
    index = 0
    while index < len(line):
        character = line[index]
        if quote:
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == quote:
                quote = None
            index += 1
            continue

        if character == "#" or line.startswith("//", index):
            break
        if line.startswith("${{", index):
            placeholder_end = line.find("}}", index + 3)
            if placeholder_end != -1:
                index = placeholder_end + 2
                continue
        if line.startswith("${", index):
            placeholder_end = line.find("}", index + 2)
            if placeholder_end != -1:
                index = placeholder_end + 1
                continue

        property_boundary = index == 0 or line[index - 1] in "{[, \t"
        object_match = SECTION_OBJECT_START.match(line, index) if property_boundary else None
        if object_match:
            current_depth += 1
            section_start = (object_match.group("section").lower(), current_depth)
            index = object_match.end()
            continue

        if character in "\"'":
            quote = character
        elif character == "{":
            current_depth += 1
        elif character == "}":
            current_depth = max(0, current_depth - 1)
        index += 1
    return section_start


def scan_line(
    path: str,
    line_number: int,
    line: str,
    nested_section: str | None = None,
    direct_child_indent: int | None = None,
) -> list[Finding]:
    if FIXTURE_MARKER in line.lower() and is_test_fixture_path(path):
        return []

    findings: list[Finding] = []
    found_categories: set[str] = set()

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
        ("JWT_KEY", JWT_KEY),
        ("GEMINI_API_KEY", GEMINI_API_KEY),
        ("PASSWORD", PASSWORD),
    ):
        if has_literal_match(pattern):
            add_finding(category)

    if has_literal_match(JWT_NESTED):
        add_finding("JWT_KEY")
    if has_literal_match(GEMINI_NESTED):
        add_finding("GEMINI_API_KEY")

    indentation = len(line) - len(line.lstrip())
    is_direct_child = direct_child_indent is not None and indentation == direct_child_indent
    if nested_section == "jwt" and is_direct_child and has_literal_match(JWT_CHILD):
        add_finding("JWT_KEY")
    elif nested_section == "gemini" and is_direct_child and has_literal_match(GEMINI_CHILD):
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
        nested_section: str | None = None
        section_indent = -1
        direct_child_indent: int | None = None
        section_brace_depth: int | None = None
        awaiting_open_brace = False
        brace_depth = 0
        for line_number, line in enumerate(text.splitlines(), start=1):
            stripped = line.strip()
            indentation = len(line) - len(line.lstrip())
            is_comment_or_blank = not stripped or stripped.startswith(("#", "//"))
            opening_braces, closing_braces = structural_brace_counts(line)

            if (
                nested_section
                and section_brace_depth is None
                and not awaiting_open_brace
                and not is_comment_or_blank
                and indentation <= section_indent
            ):
                nested_section = None
                section_indent = -1
                direct_child_indent = None

            if nested_section and awaiting_open_brace and not is_comment_or_blank:
                if opening_braces and indentation <= section_indent:
                    section_brace_depth = brace_depth + 1
                    awaiting_open_brace = False
                elif indentation > section_indent:
                    awaiting_open_brace = False
                else:
                    nested_section = None
                    section_indent = -1
                    direct_child_indent = None
                    awaiting_open_brace = False

            header_match = SECTION_HEADER.match(line)
            object_start = find_section_object_start(line, brace_depth)
            section_started = header_match is not None or object_start is not None
            if object_start:
                nested_section, section_brace_depth = object_start
                section_indent = indentation
                direct_child_indent = None
                awaiting_open_brace = False
            elif header_match:
                nested_section = header_match.group("section").lower()
                section_indent = len(header_match.group("indent"))
                direct_child_indent = None
                section_brace_depth = None
                awaiting_open_brace = True

            is_section_content = (
                nested_section
                and not section_started
                and not is_comment_or_blank
                and indentation > section_indent
                and stripped not in {"{", "}", "},"}
            )
            if is_section_content and direct_child_indent is None:
                direct_child_indent = indentation

            findings.extend(
                scan_line(
                    entry.path,
                    line_number,
                    line,
                    nested_section,
                    direct_child_indent,
                )
            )

            brace_depth = max(0, brace_depth + opening_braces - closing_braces)
            if section_brace_depth is not None and brace_depth < section_brace_depth:
                nested_section = None
                section_indent = -1
                direct_child_indent = None
                section_brace_depth = None
                awaiting_open_brace = False
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
