#!/usr/bin/env python3
"""YAML hygiene and Secret-encryption policy for tracked manifests.

Usage:
    scripts/validate-manifests.py [path ...]

With no arguments it checks every tracked *.yaml / *.yml file.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import yaml

EXEMPTION_ANNOTATION = "homelab.dev/plaintext-reason"
SOPS_VALUE_PREFIX = "ENC["
SECRET_DATA_FIELDS = ("data", "stringData")
SKIP_FILES = {"clusters/production/flux-system/gotk-components.yaml"}


class DuplicateKeyLoader(yaml.SafeLoader):
    pass


def _no_duplicate_keys(loader: yaml.Loader, node: yaml.MappingNode, deep: bool = False):
    mapping = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in mapping:
            raise yaml.constructor.ConstructorError(
                "while constructing a mapping",
                node.start_mark,
                f"found duplicate key {key!r}",
                key_node.start_mark,
            )
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


DuplicateKeyLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _no_duplicate_keys
)


def tracked_yaml_files() -> list[Path]:
    out = subprocess.run(
        ["git", "ls-files", "-z", "*.yaml", "*.yml"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return [Path(p) for p in out.split("\0") if p]


def check_secret(doc: dict, path: Path, index: int, errors: list[str]) -> None:
    where = f"{path} (document {index})"
    name = (doc.get("metadata") or {}).get("name", "<unnamed>")

    annotations = ((doc.get("metadata") or {}).get("annotations")) or {}
    exemption = annotations.get(EXEMPTION_ANNOTATION)

    values: list[tuple[str, object]] = []
    for field in SECRET_DATA_FIELDS:
        block = doc.get(field)
        if isinstance(block, dict):
            values.extend((f"{field}.{k}", v) for k, v in block.items())

    plaintext = [
        key
        for key, value in values
        if not (isinstance(value, str) and value.startswith(SOPS_VALUE_PREFIX))
    ]

    if "sops" in doc:
        if plaintext:
            errors.append(
                f"{where}: Secret/{name} has a SOPS block but these values are "
                f"not encrypted: {', '.join(sorted(plaintext))}"
            )
        if exemption:
            errors.append(
                f"{where}: Secret/{name} is SOPS-encrypted, so the "
                f"{EXEMPTION_ANNOTATION} annotation is misleading - remove it."
            )
        return

    if not values:
        return

    if exemption:
        if not str(exemption).strip():
            errors.append(
                f"{where}: Secret/{name} has an empty {EXEMPTION_ANNOTATION}; "
                "state why these values are not secret."
            )
        return

    errors.append(
        f"{where}: Secret/{name} is not SOPS-encrypted "
        f"({', '.join(sorted(plaintext))}).\n"
        f"    Encrypt it:  sops --encrypt --in-place {path}\n"
        f"    Or, if the values are genuinely not secret, annotate it:\n"
        f"      metadata.annotations.{EXEMPTION_ANNOTATION}: <why>"
    )


def main(argv: list[str]) -> int:
    paths = [Path(p) for p in argv[1:]] or tracked_yaml_files()
    errors: list[str] = []
    checked = 0
    secrets = 0

    for path in paths:
        if str(path) in SKIP_FILES or not path.is_file():
            continue

        checked += 1
        try:
            docs = list(yaml.load_all(path.read_text(), Loader=DuplicateKeyLoader))
        except yaml.YAMLError as exc:
            errors.append(f"{path}: YAML does not parse: {exc}")
            continue

        for index, doc in enumerate(docs):
            if not isinstance(doc, dict):
                continue
            if doc.get("kind") == "Secret" and doc.get("apiVersion") == "v1":
                secrets += 1
                check_secret(doc, path, index, errors)

    if errors:
        print(f"::error::{len(errors)} manifest policy violation(s)", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    print(
        f"OK: {checked} YAML files parsed, "
        f"{secrets} Secret document(s) all encrypted or exempt"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
