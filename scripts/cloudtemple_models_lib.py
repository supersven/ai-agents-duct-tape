"""Pure transforms for the Cloud Temple model catalog: JSON cache <-> Nix."""
import json
import os


def load_models(path):
    if not os.path.exists(path):
        raise FileNotFoundError(f"{path} not found; run with --fetch first")
    with open(path) as f:
        payload = json.load(f)
    return payload.get("data", [])


def _nix_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def render_models_nix(models):
    lines = ["{", "  models = {"]
    for model in sorted(models, key=lambda m: m["id"]):
        key = _nix_string(model["id"])
        lines.append(f"    {key} = {{")
        lines.append(f"      name = {key};")
        lines.append("    };")
    lines.append("  };")
    lines.append("}")
    return "\n".join(lines) + "\n"
