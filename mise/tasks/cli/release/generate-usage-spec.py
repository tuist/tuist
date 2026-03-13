#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ENV_PATTERN = re.compile(r"\s*\(env:\s*([^)]+)\)")
DEPRECATED_TOKENS = ("[Deprecated]", "[deprecated]")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate a usage-spec KDL file for the Tuist CLI.")
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--schema", type=Path, help="Path to a JSON schema produced by --experimental-dump-help.")
    source.add_argument("--tuist-path", type=Path, help="Path to a tuist binary to query with --experimental-dump-help.")
    parser.add_argument("--output", type=Path, required=True, help="Path to the output .kdl file.")
    return parser.parse_args()


def load_schema(args: argparse.Namespace) -> dict:
    if args.schema:
        return json.loads(args.schema.read_text())

    with tempfile.TemporaryDirectory() as temporary_directory:
        result = subprocess.run(
            [str(args.tuist_path), "--experimental-dump-help", "--path", temporary_directory],
            check=True,
            capture_output=True,
            text=True,
        )
        return json.loads(result.stdout)


def clean_help(text: str | None) -> tuple[str | None, str | None]:
    if not text:
        return None, None

    env_var = None
    env_match = ENV_PATTERN.search(text)
    if env_match:
        env_var = env_match.group(1)
        text = ENV_PATTERN.sub("", text)

    for token in DEPRECATED_TOKENS:
        text = text.replace(token, "")

    text = " ".join(text.split()).strip()
    return (text or None), env_var


def kdl_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def kdl_value(value: object) -> str:
    if isinstance(value, bool):
        return "#true" if value else "#false"
    if isinstance(value, (int, float)):
        return str(value)
    return kdl_string(str(value))


def node_parameters(parameters: list[tuple[str, object]]) -> str:
    if not parameters:
        return ""
    return " " + " ".join(f"{key}={kdl_value(value)}" for key, value in parameters)


def usage_value_name(argument: dict) -> str:
    completion = argument.get("completionKind") or {}
    if "directory" in completion:
        return "dir"
    if "file" in completion:
        return "file"
    return argument["valueName"]


def positional_signature(argument: dict) -> str:
    value_name = usage_value_name(argument)
    if argument["isOptional"]:
        return f"[{value_name}]"
    if argument["isRepeating"]:
        return f"<{value_name}>..."
    return f"<{value_name}>"


def ordered_names(argument: dict) -> list[str]:
    short_names = [f'-{name["name"]}' for name in argument.get("names", []) if name["kind"] == "short"]
    long_names = [f'--{name["name"]}' for name in argument.get("names", []) if name["kind"] == "long"]
    return short_names + long_names


def preferred_long_name(argument: dict) -> str | None:
    preferred = argument.get("preferredName")
    if preferred and preferred.get("kind") == "long":
        return f'--{preferred["name"]}'

    for name in argument.get("names", []):
        if name["kind"] == "long":
            return f'--{name["name"]}'
    return None


def flag_signature(argument: dict) -> str:
    names = ordered_names(argument)
    if argument["kind"] == "option":
        names.append(f'<{usage_value_name(argument)}>')
    return " ".join(names)


def argument_parameters(argument: dict) -> tuple[list[tuple[str, object]], list[str]]:
    parameters: list[tuple[str, object]] = []
    children: list[str] = []

    help_text, env_var = clean_help(argument.get("abstract"))
    if help_text:
        parameters.append(("help", help_text))
    if env_var:
        parameters.append(("env", env_var))
    if not argument.get("shouldDisplay", True):
        parameters.append(("hide", True))
    if argument.get("isRepeating") and not (argument["kind"] == "positional" and not argument["isOptional"]):
        parameters.append(("var", True))

    default_value = argument.get("defaultValue")
    if argument["kind"] == "flag":
        if argument.get("usageDefault") is not None:
            parameters.append(("default", argument["usageDefault"]))
        if argument.get("usageNegate"):
            parameters.append(("negate", argument["usageNegate"]))
    elif default_value not in (None, ""):
        parameters.append(("default", default_value))

    if argument.get("parsingStrategy") == "postTerminator":
        parameters.append(("double_dash", "required"))

    choices = argument.get("allValues")
    if not choices:
        completion = argument.get("completionKind") or {}
        choices = (completion.get("list") or {}).get("values")
    if choices:
        rendered_choices = " ".join(kdl_string(choice) for choice in choices)
        children.append(f"choices {rendered_choices}")

    return parameters, children


def long_names(argument: dict) -> list[str]:
    return [f'--{name["name"]}' for name in argument.get("names", []) if name["kind"] == "long"]


def compatible_negation(positive: dict, negative: dict) -> bool:
    positive_help, positive_env = clean_help(positive.get("abstract"))
    negative_help, negative_env = clean_help(negative.get("abstract"))
    return positive_help == negative_help and positive_env == negative_env


def normalized_arguments(arguments: list[dict]) -> list[dict]:
    by_long_name = {}
    for argument in arguments:
        for long_name in long_names(argument):
            by_long_name[long_name] = argument

    skipped = set()
    normalized: list[dict] = []

    for argument in arguments:
        argument_id = id(argument)
        if argument_id in skipped:
            continue

        if argument["kind"] == "flag":
            primary_long_name = preferred_long_name(argument)
            if primary_long_name and not primary_long_name.startswith("--no-"):
                negative_flag = by_long_name.get(f'--no-{primary_long_name[2:]}')
                if negative_flag and compatible_negation(argument, negative_flag):
                    merged_argument = dict(argument)
                    merged_argument["usageNegate"] = preferred_long_name(negative_flag) or f'--no-{primary_long_name[2:]}'
                    if argument.get("defaultValue") == primary_long_name:
                        merged_argument["usageDefault"] = True
                    skipped.add(id(negative_flag))
                    normalized.append(merged_argument)
                    continue

        normalized.append(argument)

    return normalized


def render_argument(argument: dict, indent: int) -> list[str]:
    keyword = "arg" if argument["kind"] == "positional" else "flag"
    signature = positional_signature(argument) if argument["kind"] == "positional" else flag_signature(argument)
    parameters, children = argument_parameters(argument)
    indentation = "  " * indent
    line_prefix = f"{indentation}{keyword} {kdl_string(signature)}"

    if not children:
        return [f"{line_prefix}{node_parameters(parameters)}"]

    lines = [f"{line_prefix}{node_parameters(parameters)} {{"]
    for child in children:
        lines.append(f"{indentation}  {child}")
    lines.append(f"{indentation}}}")
    return lines


def command_parameters(command: dict) -> list[tuple[str, object]]:
    parameters: list[tuple[str, object]] = []
    help_text, _ = clean_help(command.get("abstract"))
    if help_text:
        parameters.append(("help", help_text))
    if not command.get("shouldDisplay", True):
        parameters.append(("hide", True))
    return parameters


def render_command(command: dict, indent: int = 0) -> list[str]:
    parameters = command_parameters(command)
    indentation = "  " * indent
    header = f"{indentation}cmd {kdl_string(command['commandName'])}{node_parameters(parameters)}"

    items = []
    for argument in normalized_arguments(command.get("arguments", [])):
        items.extend(render_argument(argument, indent + 1))
    for subcommand in command.get("subcommands", []):
        items.extend(render_command(subcommand, indent + 1))

    if not items:
        return [header]

    lines = [f"{header} {{"]
    lines.extend(items)
    lines.append(f"{indentation}}}")
    return lines


def main() -> int:
    args = parse_args()
    schema = load_schema(args)
    command = schema.get("command", schema)

    lines = [
        "// Generated from `tuist --experimental-dump-help`.",
        "// This file is published as a release artifact in usage-spec KDL format.",
        *render_command(command),
        "",
    ]

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
