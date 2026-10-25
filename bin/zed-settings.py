#!/usr/bin/env python3
"""Read or replace the top-level `theme` value in Zed's JSONC settings.

Zed keeps comments and trailing commas in settings.json, so using a normal
JSON parser would rewrite the file. This only touches the bytes that make up
the top-level `theme` value and leaves everything else intact.
"""

import json
import sys


def skip_ws(text, i):
    while i < len(text):
        if text[i] in " \t\r\n":
            i += 1
        elif text.startswith("//", i):
            end = text.find("\n", i)
            i = len(text) if end < 0 else end + 1
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            i = len(text) if end < 0 else end + 2
        else:
            break
    return i


def skip_string(text, i):
    i += 1
    while i < len(text):
        if text[i] == "\\":
            i += 2
        elif text[i] == '"':
            return i + 1
        else:
            i += 1
    return i


def value_end(text, i):
    i = skip_ws(text, i)
    if i >= len(text):
        return i
    if text[i] == '"':
        return skip_string(text, i)
    if text[i] in "[{":
        stack = [text[i]]
        i += 1
        while i < len(text):
            if text[i] == '"':
                i = skip_string(text, i)
                continue
            if text.startswith("//", i):
                end = text.find("\n", i)
                i = len(text) if end < 0 else end + 1
                continue
            if text.startswith("/*", i):
                end = text.find("*/", i + 2)
                i = len(text) if end < 0 else end + 2
                continue
            if text[i] in "[{":
                stack.append(text[i])
            elif text[i] in "]}":
                if (text[i] == "}" and stack[-1] == "{") or (text[i] == "]" and stack[-1] == "["):
                    stack.pop()
                    if not stack:
                        return i + 1
            i += 1
        return i

    while i < len(text) and text[i] not in ",}":
        i += 1
    return i


def find_theme(text):
    depth = 0
    i = 0
    while i < len(text):
        if text[i] == '"':
            end = skip_string(text, i)
            token = text[i:end]
            j = skip_ws(text, end)
            if depth == 1 and j < len(text) and text[j] == ":":
                try:
                    key = json.loads(token)
                except Exception:
                    key = None
                if key == "theme":
                    start = skip_ws(text, j + 1)
                    return i, start, value_end(text, start)
            i = end
            continue
        if text.startswith("//", i):
            end = text.find("\n", i)
            i = len(text) if end < 0 else end + 1
            continue
        if text.startswith("/*", i):
            end = text.find("*/", i + 2)
            i = len(text) if end < 0 else end + 2
            continue
        if text[i] in "{[":
            depth += 1
        elif text[i] in "}]":
            depth -= 1
        i += 1
    return None


def replacement_for(text, value):
    found = find_theme(text)
    if found:
        _, start, end = found
        return text[:start] + value + text[end:]

    close = text.rfind("}")
    if close < 0:
        raise ValueError("settings file has no closing brace")
    before = text[:close].rstrip()
    if not before.endswith("{"):
        before += ","
    return before + '\n  "theme": ' + value + "\n" + text[close:]


def removal_for(text):
    found = find_theme(text)
    if not found:
        return text, False
    start, _, end = found

    after = end
    while after < len(text) and text[after] in " \t\r\n":
        after += 1
    if after < len(text) and text[after] == ",":
        end = after + 1
        while end < len(text) and text[end] in " \t\r\n":
            end += 1
        return text[:start] + text[end:], True

    before = start
    while before > 0 and text[before - 1] in " \t\r\n":
        before -= 1
    if before > 0 and text[before - 1] == ",":
        before -= 1
    return text[:before] + text[end:], True


def main():
    if len(sys.argv) < 3:
        print("usage: zed-settings.py get|set <settings.json> [json-value]", file=sys.stderr)
        return 2
    action, path = sys.argv[1], sys.argv[2]

    try:
        with open(path, "r", encoding="utf-8") as f:
            text = f.read()
    except FileNotFoundError:
        text = "{}\n"

    if action == "get":
        found = find_theme(text)
        if not found:
            print("__MISSING__")
        else:
            _, start, end = found
            print(text[start:end])
        return 0

    if action in ("set", "set-raw"):
        if len(sys.argv) < 4:
            print("missing JSON value", file=sys.stderr)
            return 2
        value = sys.argv[3]
        if action == "set":
            try:
                json.loads(value)
            except Exception as exc:
                print(f"invalid JSON value: {exc}", file=sys.stderr)
                return 2
        output = replacement_for(text, value)
        with open(path, "w", encoding="utf-8") as f:
            f.write(output)
        return 0

    if action == "remove":
        output, changed = removal_for(text)
        if changed:
            with open(path, "w", encoding="utf-8") as f:
                f.write(output)
        return 0

    print(f"unknown action: {action}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
