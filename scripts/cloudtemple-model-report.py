#!/usr/bin/env python3
# scripts/cloudtemple-model-report.py
"""Match Cloud Temple's models against modelgrep ratings and propose an agent->model mapping."""
import argparse
import json
import os
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cloudtemple_models_lib import load_models
from cloudtemple_matching import match_all

MODELGREP_URL = "https://modelgrep.com/api/v1/models"
AGENT_SLOTS = ["build", "plan", "general", "semble-search"]


def repo_root():
    cwd = os.getcwd()
    if not os.path.isfile(os.path.join(cwd, "flake.nix")):
        raise SystemExit("error: run from repo root (flake.nix not found)")
    return cwd


def _http_fetch_page(base_url, page_size, offset):
    with urllib.request.urlopen(
        f"{base_url}?limit={page_size}&offset={offset}", timeout=30
    ) as resp:
        return json.load(resp)


def do_fetch_modelgrep(data_path, fetch_page=None, base_url=MODELGREP_URL, page_size=100):
    fetch_page = fetch_page or _http_fetch_page
    models = []
    offset = 0
    while True:
        payload = fetch_page(base_url, page_size, offset)
        models.extend(payload["data"])
        if not payload.get("has_more"):
            break
        offset = payload["next_offset"]
    with open(data_path, "w") as f:
        json.dump({"data": models}, f)
    print(f"fetched {len(models)} modelgrep models -> {data_path}")


def coding_score(mg_model):
    aa = (mg_model.get("benchmarks") or {}).get("artificial_analysis") or {}
    coding = aa.get("coding")
    return coding if coding is not None else aa.get("intelligence")


def build_report(ct_models, mg_models, agent_slots=AGENT_SLOTS):
    matches, unmatched = match_all(ct_models, mg_models)
    ranked = sorted(
        (
            (ct, mg)
            for ct, mg in matches
            if (mg.get("capabilities") or {}).get("tools") and coding_score(mg) is not None
        ),
        key=lambda pair: coding_score(pair[1]),
        reverse=True,
    )
    proposal = {slot: ranked[i] for i, slot in enumerate(agent_slots) if i < len(ranked)}
    return {
        "unmatched": [ct["id"] for ct in unmatched],
        "matches": [
            {
                "cloud_temple_id": ct["id"],
                "modelgrep_id": mg["id"],
                "performance": mg.get("performance"),
                "capabilities": mg.get("capabilities"),
                "benchmarks": mg.get("benchmarks"),
            }
            for ct, mg in matches
        ],
        "proposal": {
            slot: {
                "cloud_temple_id": ct["id"],
                "modelgrep_id": mg["id"],
                "coding_score": coding_score(mg),
            }
            for slot, (ct, mg) in proposal.items()
        },
    }


def print_report(report):
    print("== Unmatched Cloud Temple models ==")
    for model_id in report["unmatched"]:
        print(f"  {model_id}")
    print()
    print("== Matched models ==")
    for m in report["matches"]:
        print(f"  {m['cloud_temple_id']} -> {m['modelgrep_id']}")
        print(f"    performance: {m['performance']}")
        print(f"    capabilities: {m['capabilities']}")
        print(f"    benchmarks: {m['benchmarks']}")
    print()
    print("== Proposed agent -> model mapping (coding-focused) ==")
    for slot, pick in report["proposal"].items():
        print(f"  {slot}: cloud-temple/{pick['cloud_temple_id']} (coding score {pick['coding_score']})")


def main(argv, fetch_fn=do_fetch_modelgrep):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fetch", action="store_true", help="refetch modelgrep ratings")
    args = parser.parse_args(argv)

    root = repo_root()
    ct_path = os.path.join(root, "data", "cloudtemple-models.json")
    mg_path = os.path.join(root, "data", "modelgrep-models.json")

    if args.fetch:
        fetch_fn(mg_path)

    ct_models = load_models(ct_path)
    mg_models = load_models(mg_path)
    print_report(build_report(ct_models, mg_models))


if __name__ == "__main__":
    main(sys.argv[1:])
