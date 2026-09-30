#!/usr/bin/env python3
# scripts/fetch-cloudtemple-models.py
"""Fetch/cache Cloud Temple's model list and regenerate the Nix model catalog."""
import argparse
import json
import os
import subprocess
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cloudtemple_models_lib import load_models, render_models_nix

API_URL = "https://api.ai.cloud-temple.com/v1/models"


def repo_root():
    cwd = os.getcwd()
    if not os.path.isfile(os.path.join(cwd, "flake.nix")):
        raise SystemExit("error: run from repo root (flake.nix not found)")
    return cwd


def do_fetch(data_path, api_url=API_URL):
    token = os.environ.get("CLOUD_TEMPLE_API_TOKEN")
    if not token:
        raise SystemExit("error: CLOUD_TEMPLE_API_TOKEN not set, required for --fetch")
    req = urllib.request.Request(api_url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        body = resp.read()
    json.loads(body)  # validate before overwriting the cache
    with open(data_path, "wb") as f:
        f.write(body)
    print(f"fetched models -> {data_path}")


def do_update(data_path, generated_path):
    models = load_models(data_path)
    raw = render_models_nix(models)
    formatted = subprocess.run(
        ["nixfmt"], input=raw, capture_output=True, text=True, check=True
    ).stdout
    os.makedirs(os.path.dirname(generated_path), exist_ok=True)
    with open(generated_path, "w") as f:
        f.write(formatted)
    print(f"regenerated {generated_path} ({len(models)} models)")


def main(argv, fetch_fn=do_fetch, update_fn=do_update):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fetch", action="store_true", help="refetch from the Cloud Temple API")
    parser.add_argument("--update", action="store_true", help="regenerate the Nix model catalog")
    args = parser.parse_args(argv)

    root = repo_root()
    data_path = os.path.join(root, "data", "cloudtemple-models.json")
    generated_path = os.path.join(
        root, "harnesses", "parts", "generated", "cloud-temple-models.nix"
    )

    if not args.fetch and not args.update:
        count = len(load_models(data_path)) if os.path.exists(data_path) else 0
        print(
            f"no-op: {count} cached models in {data_path}. "
            "Use --fetch to refetch, --update to regenerate the Nix catalog."
        )
        return

    if args.fetch:
        fetch_fn(data_path)
    if args.update:
        update_fn(data_path, generated_path)


if __name__ == "__main__":
    main(sys.argv[1:])
