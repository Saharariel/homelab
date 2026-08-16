#!/usr/bin/env python3
"""Render every HelmRelease found in pre-rendered Flux output.

Flux root rendering validates the HelmRelease object itself. It does not prove
the referenced chart exists at that version, nor that spec.values still match
the chart's schema. This does both, then re-validates the rendered workload.

Usage:
    scripts/render-helmreleases.py <rendered-manifest> [...] [--out DIR]
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

REPO_ROOT = Path(
    subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        check=True, capture_output=True, text=True,
    ).stdout.strip()
)


def load_versions() -> dict[str, str]:
    env = {}
    for line in (REPO_ROOT / ".github/ci/versions.env").read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            env[k] = v
    return env


def run(cmd: list[str], **kw) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def index_documents(paths: list[Path]):
    repos: dict[tuple[str, str], dict] = {}
    releases: list[dict] = []
    for path in paths:
        for doc in yaml.safe_load_all(path.read_text()):
            if not isinstance(doc, dict):
                continue
            kind = doc.get("kind")
            meta = doc.get("metadata") or {}
            if kind == "HelmRepository":
                repos[(meta.get("name"), meta.get("namespace"))] = doc
            elif kind == "HelmRelease":
                releases.append(doc)
    return repos, releases


def resolve_chart(release: dict, repos: dict) -> tuple[str, str, str, str]:
    spec = release["spec"]
    meta = release["metadata"]
    release_ns = meta.get("namespace", "default")

    if "chartRef" in spec:
        raise LookupError("spec.chartRef is not supported by this validator")

    chart_spec = spec["chart"]["spec"]
    source = chart_spec["sourceRef"]
    key = (source["name"], source.get("namespace", release_ns))

    if key not in repos:
        raise LookupError(
            f"HelmRepository {key[0]} in namespace {key[1]} not found in rendered output"
        )

    repo = repos[key]
    url = repo["spec"]["url"]
    repo_type = repo["spec"].get("type", "default")
    return chart_spec["chart"], chart_spec.get("version", ""), url, repo_type


def apply_post_renderers(rendered: str, post_renderers: list, workdir: Path) -> str:
    """Replay Flux spec.postRenderers through kustomize."""
    build = workdir / "postrender"
    build.mkdir(parents=True, exist_ok=True)
    (build / "resources.yaml").write_text(rendered)

    kustomization: dict = {
        "apiVersion": "kustomize.config.k8s.io/v1beta1",
        "kind": "Kustomization",
        "resources": ["resources.yaml"],
    }

    patches = []
    images = []
    for entry in post_renderers:
        kustomize = entry.get("kustomize") or {}
        patches.extend(kustomize.get("patches") or [])
        images.extend(kustomize.get("images") or [])

    if patches:
        kustomization["patches"] = patches
    if images:
        kustomization["images"] = images

    (build / "kustomization.yaml").write_text(yaml.safe_dump(kustomization))

    result = run(["kubectl", "kustomize", str(build)])
    if result.returncode != 0:
        raise RuntimeError(f"postRenderers failed:\n{result.stderr}")
    return result.stdout


def process(release: dict, repos: dict, out_dir: Path, versions: dict) -> list[str]:
    meta = release["metadata"]
    spec = release["spec"]
    name = meta["name"]
    namespace = meta.get("namespace", "default")
    release_name = spec.get("releaseName", name)
    errors: list[str] = []

    try:
        chart, version, url, repo_type = resolve_chart(release, repos)
    except LookupError as exc:
        return [f"{namespace}/{name}: {exc}"]

    print(f"  {namespace}/{name}: {chart}@{version or 'latest'} from {url}")

    with tempfile.TemporaryDirectory() as tmp:
        workdir = Path(tmp)
        chart_dir = workdir / "chart"
        chart_dir.mkdir()

        pull = ["helm", "pull", "--untar", "--untardir", str(chart_dir)]
        if repo_type == "oci":
            pull.append(f"{url.rstrip('/')}/{chart}")
        else:
            pull.extend([chart, "--repo", url])
        if version:
            pull.extend(["--version", version])

        result = run(pull)
        if result.returncode != 0:
            return [
                f"{namespace}/{name}: cannot pull {chart}@{version} from {url}\n"
                f"      {result.stderr.strip()}"
            ]

        unpacked = next(chart_dir.iterdir())

        values_file = workdir / "values.yaml"
        values_file.write_text(yaml.safe_dump(spec.get("values") or {}))

        lint = run(["helm", "lint", str(unpacked), "-f", str(values_file)])
        if lint.returncode != 0:
            errors.append(
                f"{namespace}/{name}: helm lint failed\n"
                f"      {lint.stdout.strip() or lint.stderr.strip()}"
            )

        template = run([
            "helm", "template", release_name, str(unpacked),
            "--namespace", namespace,
            "-f", str(values_file),
            "--kube-version", versions.get("KUBERNETES_VERSION", "1.33.4"),
        ])
        if template.returncode != 0:
            errors.append(
                f"{namespace}/{name}: helm template failed\n"
                f"      {template.stderr.strip()}"
            )
            return errors

        rendered = template.stdout

        if spec.get("postRenderers"):
            try:
                rendered = apply_post_renderers(rendered, spec["postRenderers"], workdir)
            except RuntimeError as exc:
                errors.append(f"{namespace}/{name}: {exc}")
                return errors

        out_file = out_dir / f"{namespace}-{name}.yaml"
        out_file.write_text(rendered)

    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifests", nargs="+", type=Path)
    parser.add_argument("--out", type=Path, default=Path("build/helm"))
    args = parser.parse_args()

    for tool in ("helm", "kubectl"):
        if not shutil.which(tool):
            print(f"render-helmreleases: {tool} not found", file=sys.stderr)
            return 1

    versions = load_versions()
    repos, releases = index_documents(args.manifests)

    if not releases:
        print("render-helmreleases: no HelmReleases found", file=sys.stderr)
        return 1

    args.out.mkdir(parents=True, exist_ok=True)
    print(f"render-helmreleases: {len(releases)} HelmRelease(s), {len(repos)} repositories")

    errors: list[str] = []
    for release in releases:
        errors.extend(process(release, repos, args.out, versions))

    if errors:
        print(f"::error::{len(errors)} HelmRelease failure(s)", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    print(f"render-helmreleases: all {len(releases)} rendered into {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
