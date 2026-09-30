# Cloud Temple Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Cloud Temple as an opencode model provider, a hand-curated agent->model mapping, an `enrichWithLLMaaS` function exposing `<harness>-llmaas` variants, and two Python scripts that fetch/cache Cloud Temple's and modelgrep's model data and propose a coding-focused mapping.

**Architecture:** Two new harness parts (`cloud-temple.nix` constant provider config + `generated/cloud-temple-models.nix` generated model catalog; `cloud-temple-agents.nix` constant curated mapping), one new `lib/mkHarness.nix` function (`enrichWithLLMaaS`) wired into `vanilla-dev` and `superpowers`, and two standalone Python CLI scripts with their pure logic factored into importable, unit-tested library modules.

**Tech Stack:** Nix (parts/harness composition, existing `mkHarness`/`evalHarness` machinery), Python 3 stdlib only (`argparse`, `urllib.request`, `json`, `subprocess`) — no new runtime dependencies, `unittest` for tests (matches: no pytest/test infra exists yet in this repo, stdlib avoids adding one).

**Spec:** `docs/superpowers/specs/2026-09-30-cloud-temple-support-design.md`

## Global Constraints

- Provider id: `cloud-temple`. npm: `@ai-sdk/openai-compatible`. `options.baseURL = "https://api.ai.cloud-temple.com/v1"`. `options.apiKey = "{env:CLOUD_TEMPLE_API_TOKEN}"`.
- `data/cloudtemple-models.json` and `data/modelgrep-models.json` are the only on-disk caches; both scripts default to using them and only touch the network on an explicit flag.
- `harnesses/parts/generated/cloud-temple-models.nix` is machine output — only `fetch-cloudtemple-models.py --update` writes it, never hand-edited.
- `enrichWithLLMaaS` suffixes the harness name with `-llmaas` and threads `wrapArgs` through unchanged. The API key is NOT jailed into the harness: `CLOUD_TEMPLE_API_TOKEN` is opencode's own runtime credential (read from the environment / `auth.json`), and jailing it via `wrapArgs` conflicted with that mechanism.
- Curated agent slots: `build`, `plan`, `general`, `semble-search`. Values are hand-picked (best-guess), not auto-written by the report script.
- Matching (Cloud Temple id <-> modelgrep entry) requires org/maker agreement, base-name token overlap, and weight agreement (`abs(diff) <= max(1.0, 0.15 * max(a,b))`) — all three, best-effort.
- Dashed provider/agent keys need bracket form in jq assertions: `.provider["cloud-temple"]`, `.agent["semble-search"]` (per `creating-harness-parts` Common Mistakes).

## Review Focus

- `--fetch` invoked without `CLOUD_TEMPLE_API_TOKEN` set — must fail with a clear message, not an opaque 401/traceback.
- Either script run with no cached data file and no fetch flag — must fail with a clear "run with --fetch first" message, not a raw `FileNotFoundError` traceback.
- modelgrep pagination (`has_more`/`next_offset`) — must follow every page, not just the first; a truncated fetch would silently under-report ratings.
- Curated model ids in `cloud-temple-agents.nix` must actually exist in the generated catalog — catalog regeneration (id renames on Cloud Temple's side) shouldn't silently leave a dangling reference; caught by the `checks.*-llmaas` jq assertions cross-checked against Task 5's own catalog inspection.
- Empty/degenerate model list (`data` array missing or empty) — `render_models_nix` must produce a valid, still-nixfmt-clean empty attrset, not throw or emit invalid Nix.

---

### Task 1: Cloud Temple model catalog transform library

**Files:**
- Create: `scripts/cloudtemple_models_lib.py`
- Test: `scripts/test_cloudtemple_models_lib.py`

**Interfaces:**
- Produces: `load_models(path: str) -> list[dict]` (raises `FileNotFoundError` with a "--fetch" hint if `path` doesn't exist), `render_models_nix(models: list[dict]) -> str` (pure, deterministic, sorted by `id`).

- [ ] **Step 1: Write the failing tests**

```python
# scripts/test_cloudtemple_models_lib.py
import json
import os
import tempfile
import unittest

from cloudtemple_models_lib import load_models, render_models_nix


class RenderModelsNixTests(unittest.TestCase):
    def test_empty_list_renders_empty_attrset(self):
        self.assertEqual(render_models_nix([]), "{\n  models = {\n  };\n}\n")

    def test_renders_sorted_by_id(self):
        models = [{"id": "b-model"}, {"id": "a-model"}]
        out = render_models_nix(models)
        self.assertLess(out.index('"a-model"'), out.index('"b-model"'))

    def test_renders_name_equal_to_id(self):
        out = render_models_nix([{"id": "qwen3.6:27b"}])
        self.assertIn('"qwen3.6:27b" = {', out)
        self.assertIn('name = "qwen3.6:27b";', out)

    def test_escapes_quotes_in_id(self):
        out = render_models_nix([{"id": 'weird"id'}])
        self.assertIn('weird\\"id', out)


class LoadModelsTests(unittest.TestCase):
    def test_missing_file_raises_clear_error(self):
        with self.assertRaises(FileNotFoundError) as ctx:
            load_models("/nonexistent/path.json")
        self.assertIn("--fetch", str(ctx.exception))

    def test_loads_data_array(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "models.json")
            with open(path, "w") as f:
                json.dump({"data": [{"id": "x"}]}, f)
            self.assertEqual(load_models(path), [{"id": "x"}])


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd scripts && python3 -m unittest test_cloudtemple_models_lib -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'cloudtemple_models_lib'`

- [ ] **Step 3: Write the implementation**

```python
# scripts/cloudtemple_models_lib.py
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd scripts && python3 -m unittest test_cloudtemple_models_lib -v`
Expected: PASS (6 tests)

- [ ] **Step 5: Commit**

```bash
git add scripts/cloudtemple_models_lib.py scripts/test_cloudtemple_models_lib.py
git commit -m "feat: add Cloud Temple model catalog transform library"
```

---

### Task 2: `fetch-cloudtemple-models.py` CLI

**Files:**
- Create: `scripts/fetch-cloudtemple-models.py`
- Test: `scripts/test_fetch_cloudtemple_models.py`

**Interfaces:**
- Consumes: `load_models`, `render_models_nix` from Task 1 (`cloudtemple_models_lib`).
- Produces: `main(argv, fetch_fn=do_fetch, update_fn=do_update)`, `do_fetch(data_path, api_url=API_URL)`, `do_update(data_path, generated_path)`, `repo_root()`.

- [ ] **Step 1: Write the failing tests**

```python
# scripts/test_fetch_cloudtemple_models.py
import importlib.util
import io
import json
import os
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest import mock

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "fetch_cloudtemple_models", os.path.join(_HERE, "fetch-cloudtemple-models.py")
)
fetch_cloudtemple_models = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(fetch_cloudtemple_models)


class MainDispatchTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.prev_cwd = os.getcwd()
        os.chdir(self.tmp.name)
        open("flake.nix", "w").close()
        os.makedirs("data", exist_ok=True)
        with open("data/cloudtemple-models.json", "w") as f:
            json.dump({"data": [{"id": "a"}, {"id": "b"}]}, f)

    def tearDown(self):
        os.chdir(self.prev_cwd)

    def test_no_flags_prints_status_and_calls_nothing(self):
        calls = []
        buf = io.StringIO()
        with redirect_stdout(buf):
            fetch_cloudtemple_models.main(
                [],
                fetch_fn=lambda *a: calls.append("fetch"),
                update_fn=lambda *a: calls.append("update"),
            )
        self.assertEqual(calls, [])
        self.assertIn("2 cached models", buf.getvalue())

    def test_fetch_only_calls_fetch_not_update(self):
        calls = []
        fetch_cloudtemple_models.main(
            ["--fetch"],
            fetch_fn=lambda *a: calls.append("fetch"),
            update_fn=lambda *a: calls.append("update"),
        )
        self.assertEqual(calls, ["fetch"])

    def test_update_only_calls_update_not_fetch(self):
        calls = []
        fetch_cloudtemple_models.main(
            ["--update"],
            fetch_fn=lambda *a: calls.append("fetch"),
            update_fn=lambda *a: calls.append("update"),
        )
        self.assertEqual(calls, ["update"])

    def test_fetch_and_update_calls_both_in_order(self):
        calls = []
        fetch_cloudtemple_models.main(
            ["--fetch", "--update"],
            fetch_fn=lambda *a: calls.append("fetch"),
            update_fn=lambda *a: calls.append("update"),
        )
        self.assertEqual(calls, ["fetch", "update"])

    def test_missing_flake_nix_errors(self):
        os.remove("flake.nix")
        with self.assertRaises(SystemExit):
            fetch_cloudtemple_models.main([])


class DoFetchTests(unittest.TestCase):
    def test_missing_token_raises_clear_error(self):
        with mock.patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(SystemExit) as ctx:
                fetch_cloudtemple_models.do_fetch("/tmp/unused.json")
        self.assertIn("CLOUD_TEMPLE_API_TOKEN", str(ctx.exception))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd scripts && python3 -m unittest test_fetch_cloudtemple_models -v`
Expected: FAIL — `fetch-cloudtemple-models.py` doesn't exist yet (loader error).

- [ ] **Step 3: Write the implementation**

```python
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
```

- [ ] **Step 4: Make it executable and run tests to verify they pass**

Run: `chmod +x scripts/fetch-cloudtemple-models.py && cd scripts && python3 -m unittest test_fetch_cloudtemple_models -v`
Expected: PASS (6 tests)

- [ ] **Step 5: Generate the real catalog from the already-fetched data**

The repo already has `data/cloudtemple-models.json` (from the `curl` in `task.md`). Regenerate the Nix catalog from it (needs `nixfmt` on `PATH` — enter the flake devShell or `nix-shell -p nixfmt`):

Run: `nixfmt --version && python3 scripts/fetch-cloudtemple-models.py --update`
Expected: prints `regenerated harnesses/parts/generated/cloud-temple-models.nix (43 models)`; inspect the file — it should contain a `models` attrset with 43 entries, each `name` equal to its key.

- [ ] **Step 6: Commit**

```bash
git add scripts/fetch-cloudtemple-models.py scripts/test_fetch_cloudtemple_models.py \
        harnesses/parts/generated/cloud-temple-models.nix data/cloudtemple-models.json
git commit -m "feat: add fetch-cloudtemple-models.py, generate Cloud Temple model catalog"
```

---

### Task 3: `cloud-temple.nix` provider part

**Files:**
- Create: `harnesses/parts/cloud-temple.nix`

**Interfaces:**
- Consumes: `harnesses/parts/generated/cloud-temple-models.nix` (Task 2's `models` attrset).
- Produces: a module with `config.opencode.provider.cloud-temple`, importable as `import ./parts/cloud-temple.nix { }` from a harness's `modules` list.

- [ ] **Step 1: Write the part**

```nix
# harnesses/parts/cloud-temple.nix
{ }:
{
  config.opencode.provider.cloud-temple = {
    npm = "@ai-sdk/openai-compatible";
    name = "Cloud Temple";
    options.baseURL = "https://api.ai.cloud-temple.com/v1";
    options.apiKey = "{env:CLOUD_TEMPLE_API_TOKEN}";
    models = (import ./generated/cloud-temple-models.nix).models;
  };
}
```

- [ ] **Step 2: Verify it evaluates and exposes the expected values**

Run:
```bash
nix eval --file harnesses/parts/cloud-temple.nix --apply \
  'f: let c = (f {}).config.opencode.provider.cloud-temple; in [ c.npm c.options.baseURL (builtins.hasAttr "qwen-coder-next:80b" c.models) ]'
```
Expected: `[ "@ai-sdk/openai-compatible" "https://api.ai.cloud-temple.com/v1" true ]`

- [ ] **Step 3: Commit**

```bash
git add harnesses/parts/cloud-temple.nix
git commit -m "feat: add cloud-temple.nix provider part"
```

---

### Task 4: `cloud-temple-agents.nix` curated mapping part

**Files:**
- Create: `harnesses/parts/cloud-temple-agents.nix`

**Interfaces:**
- Consumes: model ids from Task 2's generated catalog (must exist as keys there).
- Produces: a module with `config.opencode.agent.<slot>.model` for `build`, `plan`, `general`, `semble-search`.

Picks (best-guess, coding-focused, from the 43 models in `data/cloudtemple-models.json`): `build` gets the explicit coder model; `plan` gets a large general reasoning model; `general` a smaller/faster default; `semble-search` (a narrow structural-search subagent) a small, cheap model. Revisit after Task 7's report has run once against real modelgrep data.

- [ ] **Step 1: Write the part**

```nix
# harnesses/parts/cloud-temple-agents.nix
{ }:
{
  config.opencode.agent = {
    build.model = "cloud-temple/qwen-coder-next:80b";
    plan.model = "cloud-temple/qwen3.6:35b";
    general.model = "cloud-temple/qwen3.6:27b";
    "semble-search".model = "cloud-temple/qwen3.5:9b";
  };
}
```

- [ ] **Step 2: Verify every referenced model id exists in the generated catalog**

```bash
nix eval --file harnesses/parts/cloud-temple-agents.nix --apply '
  agents: let
    g = (import ./harnesses/parts/generated/cloud-temple-models.nix).models;
    ids = builtins.map (a: builtins.elemAt (builtins.split "/" a.model) 2) [
      agents.config.opencode.agent.build
      agents.config.opencode.agent.plan
      agents.config.opencode.agent.general
      agents.config.opencode.agent."semble-search"
    ];
  in builtins.all (id: builtins.hasAttr id g) ids
'
```
Expected: `true`. (Run from repo root so the relative import resolves.)

- [ ] **Step 3: Commit**

```bash
git add harnesses/parts/cloud-temple-agents.nix
git commit -m "feat: add cloud-temple-agents.nix curated agent->model mapping"
```

---

### Task 5: Cloud Temple <-> modelgrep matching library

**Files:**
- Create: `scripts/cloudtemple_matching.py`
- Test: `scripts/test_cloudtemple_matching.py`

**Interfaces:**
- Produces: `parse_org_and_family(id: str) -> (str|None, str)`, `parse_params_b(id: str) -> float|None`, `name_tokens(s: str) -> set[str]`, `weights_match(a: float|None, b: float|None) -> bool`, `find_match(ct_model: dict, mg_models: list[dict]) -> dict|None`, `match_all(ct_models, mg_models) -> (list[tuple], list[dict])`.

- [ ] **Step 1: Write the failing tests**

```python
# scripts/test_cloudtemple_matching.py
import unittest

from cloudtemple_matching import (
    find_match,
    match_all,
    parse_org_and_family,
    parse_params_b,
    weights_match,
)

MG_FIXTURES = [
    {
        "id": "qwen/qwen3.8-27b",
        "maker": "qwen",
        "hugging_face_id": "Qwen/Qwen3.8-27B",
        "open_weights": {"params_b": 27.8},
    },
    {
        "id": "google/gemma-4-31b-it",
        "maker": "google",
        "hugging_face_id": "google/gemma-4-31B-it",
        "open_weights": {"params_b": 31.3},
    },
    {
        "id": "mistralai/ministral-3b-2512",
        "maker": "mistralai",
        "hugging_face_id": "mistralai/Ministral-3-3B-Instruct-2512",
        "open_weights": {"params_b": 3.8},
    },
]


class ParsingTests(unittest.TestCase):
    def test_parse_org_and_family_slash_form(self):
        org, family = parse_org_and_family("Qwen/Qwen3.8-27B-FP8")
        self.assertEqual(org, "qwen")
        self.assertEqual(family, "Qwen3.8-27B-FP8")

    def test_parse_org_and_family_bare_tag_resolves_maker(self):
        org, _ = parse_org_and_family("gemma4:31b")
        self.assertEqual(org, "google")

    def test_parse_org_and_family_unresolvable_family(self):
        org, _ = parse_org_and_family("mediphi-clinical:4b")
        self.assertIsNone(org)

    def test_parse_params_b_billions(self):
        self.assertEqual(parse_params_b("gemma4:31b"), 31.0)

    def test_parse_params_b_millions(self):
        self.assertEqual(parse_params_b("bge-m3:567m"), 0.567)

    def test_weights_match_small_model_absolute_tolerance(self):
        self.assertTrue(weights_match(3.0, 3.8))

    def test_weights_match_large_model_relative_tolerance(self):
        self.assertTrue(weights_match(120.0, 116.8))
        self.assertFalse(weights_match(120.0, 90.0))


class FindMatchTests(unittest.TestCase):
    def test_matches_slash_form_by_org_name_and_weight(self):
        mg = find_match({"id": "Qwen/Qwen3.8-27B-FP8"}, MG_FIXTURES)
        self.assertIsNotNone(mg)
        self.assertEqual(mg["id"], "qwen/qwen3.8-27b")

    def test_matches_bare_tag_via_family_lookup(self):
        mg = find_match({"id": "gemma4:31b"}, MG_FIXTURES)
        self.assertIsNotNone(mg)
        self.assertEqual(mg["id"], "google/gemma-4-31b-it")

    def test_matches_within_absolute_weight_tolerance(self):
        mg = find_match({"id": "Ministral-3-3B-Instruct-2512-Q8_0.gguf"}, MG_FIXTURES)
        self.assertIsNotNone(mg)
        self.assertEqual(mg["id"], "mistralai/ministral-3b-2512")

    def test_no_match_for_embedding_model(self):
        self.assertIsNone(find_match({"id": "bge-m3:567m"}, MG_FIXTURES))


class MatchAllTests(unittest.TestCase):
    def test_splits_matched_and_unmatched(self):
        ct_models = [{"id": "gemma4:31b"}, {"id": "bge-m3:567m"}]
        matches, unmatched = match_all(ct_models, MG_FIXTURES)
        self.assertEqual(len(matches), 1)
        self.assertEqual(len(unmatched), 1)
        self.assertEqual(unmatched[0]["id"], "bge-m3:567m")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd scripts && python3 -m unittest test_cloudtemple_matching -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'cloudtemple_matching'`

- [ ] **Step 3: Write the implementation**

```python
# scripts/cloudtemple_matching.py
"""Best-effort structural matching between Cloud Temple and modelgrep models."""
import re

FAMILY_TO_MAKER = {
    "ministral": "mistralai",
    "devstral": "mistralai",
    "nemotron": "nvidia",
    "granite": "ibm",
    "mistral": "mistralai",
    "gpt-oss": "openai",
    "voxtral": "mistralai",
    "gemma": "google",
    "llama": "meta-llama",
    "qwen": "qwen",
}

NOISE_TOKENS = {"instruct", "chat", "it", "base", "preview", "free", "next"}

_SIZE_RE = re.compile(r"(\d+(?:\.\d+)?)\s*([bBmM])\b")


def parse_org_and_family(cloudtemple_id):
    if "/" in cloudtemple_id:
        org, family = cloudtemple_id.split("/", 1)
        return org.lower(), family
    family = cloudtemple_id.split(":", 1)[0]
    lowered = family.lower()
    for key in sorted(FAMILY_TO_MAKER, key=len, reverse=True):
        if key in lowered:
            return FAMILY_TO_MAKER[key], family
    return None, family


def parse_params_b(cloudtemple_id):
    match = _SIZE_RE.search(cloudtemple_id)
    if not match:
        return None
    value = float(match.group(1))
    if match.group(2).lower() == "m":
        value /= 1000
    return value


def name_tokens(s):
    s = re.sub(r"\.gguf$", "", s, flags=re.I)
    s = re.sub(r"(?<=[A-Za-z])(?=\d)", " ", s)
    s = re.sub(r"[^A-Za-z0-9]+", " ", s)
    tokens = {t.lower() for t in s.split()}
    tokens = {
        t for t in tokens if not re.fullmatch(r"\d+b|\d+m|fp\d+|q\d\w*|bf16|awq|gptq", t)
    }
    return tokens - NOISE_TOKENS


def weights_match(a, b):
    if a is None or b is None:
        return False
    return abs(a - b) <= max(1.0, 0.15 * max(a, b))


def find_match(ct_model, mg_models):
    org, family = parse_org_and_family(ct_model["id"])
    params_b = parse_params_b(ct_model["id"])
    if org is None or params_b is None:
        return None
    ct_tokens = name_tokens(family)
    for mg in mg_models:
        maker = (mg.get("maker") or "").lower()
        hf_id = mg.get("hugging_face_id") or ""
        hf_org = hf_id.split("/", 1)[0].lower() if "/" in hf_id else ""
        if org != maker and org != hf_org:
            continue
        mg_params = (mg.get("open_weights") or {}).get("params_b")
        if not weights_match(params_b, mg_params):
            continue
        mg_name_source = hf_id.split("/", 1)[1] if "/" in hf_id else mg.get("id", "")
        if ct_tokens & name_tokens(mg_name_source):
            return mg
    return None


def match_all(ct_models, mg_models):
    matches = []
    unmatched = []
    for ct in ct_models:
        mg = find_match(ct, mg_models)
        if mg is None:
            unmatched.append(ct)
        else:
            matches.append((ct, mg))
    return matches, unmatched
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd scripts && python3 -m unittest test_cloudtemple_matching -v`
Expected: PASS (10 tests)

- [ ] **Step 5: Commit**

```bash
git add scripts/cloudtemple_matching.py scripts/test_cloudtemple_matching.py
git commit -m "feat: add Cloud Temple <-> modelgrep matching library"
```

---

### Task 6: `cloudtemple-model-report.py` CLI

**Files:**
- Create: `scripts/cloudtemple-model-report.py`
- Test: `scripts/test_cloudtemple_model_report.py`

**Interfaces:**
- Consumes: `load_models` (Task 1), `match_all` (Task 5).
- Produces: `main(argv, fetch_fn=do_fetch_modelgrep)`, `do_fetch_modelgrep(data_path, fetch_page=None, base_url=MODELGREP_URL, page_size=100)`, `build_report(ct_models, mg_models, agent_slots=AGENT_SLOTS) -> dict`, `coding_score(mg_model) -> float|None`, `print_report(report)`.

- [ ] **Step 1: Write the failing tests**

```python
# scripts/test_cloudtemple_model_report.py
import importlib.util
import json
import os
import tempfile
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "cloudtemple_model_report", os.path.join(_HERE, "cloudtemple-model-report.py")
)
cloudtemple_model_report = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(cloudtemple_model_report)

build_report = cloudtemple_model_report.build_report
coding_score = cloudtemple_model_report.coding_score
do_fetch_modelgrep = cloudtemple_model_report.do_fetch_modelgrep

MG_FIXTURES = [
    {
        "id": "qwen/qwen-coder-next",
        "maker": "qwen",
        "hugging_face_id": "Qwen/Qwen3-Coder-Next",
        "open_weights": {"params_b": 79.7},
        "capabilities": {"tools": True},
        "performance": {"throughput_tps": 50},
        "benchmarks": {"artificial_analysis": {"coding": 60.0, "intelligence": 55.0}},
    },
    {
        "id": "qwen/qwen3.6-27b",
        "maker": "qwen",
        "hugging_face_id": "Qwen/Qwen3.6-27B",
        "open_weights": {"params_b": 27.8},
        "capabilities": {"tools": True},
        "performance": {"throughput_tps": 90},
        "benchmarks": {"artificial_analysis": {"coding": 40.0, "intelligence": 50.0}},
    },
]

CT_MODELS = [{"id": "qwen-coder-next:80b"}, {"id": "qwen3.6:27b"}, {"id": "bge-m3:567m"}]


class BuildReportTests(unittest.TestCase):
    def test_unmatched_includes_non_llm_models(self):
        report = build_report(CT_MODELS, MG_FIXTURES)
        self.assertIn("bge-m3:567m", report["unmatched"])

    def test_matches_carry_metrics(self):
        report = build_report(CT_MODELS, MG_FIXTURES)
        match = next(m for m in report["matches"] if m["cloud_temple_id"] == "qwen-coder-next:80b")
        self.assertEqual(match["performance"]["throughput_tps"], 50)

    def test_proposal_ranks_by_coding_score_descending(self):
        report = build_report(CT_MODELS, MG_FIXTURES, agent_slots=["build", "plan"])
        self.assertEqual(report["proposal"]["build"]["cloud_temple_id"], "qwen-coder-next:80b")
        self.assertEqual(report["proposal"]["plan"]["cloud_temple_id"], "qwen3.6:27b")

    def test_proposal_skips_models_without_tools(self):
        no_tools = [dict(MG_FIXTURES[0], capabilities={"tools": False})]
        report = build_report([CT_MODELS[0]], no_tools, agent_slots=["build"])
        self.assertEqual(report["proposal"], {})


class CodingScoreTests(unittest.TestCase):
    def test_falls_back_to_intelligence_when_coding_missing(self):
        mg = {"benchmarks": {"artificial_analysis": {"coding": None, "intelligence": 42.0}}}
        self.assertEqual(coding_score(mg), 42.0)


class FetchPaginationTests(unittest.TestCase):
    def test_follows_has_more_until_exhausted(self):
        pages = [
            {"data": [{"id": "a"}], "has_more": True, "next_offset": 1},
            {"data": [{"id": "b"}], "has_more": False, "next_offset": None},
        ]
        calls = []

        def fake_fetch_page(base_url, page_size, offset):
            calls.append(offset)
            return pages[len(calls) - 1]

        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "modelgrep-models.json")
            do_fetch_modelgrep(path, fetch_page=fake_fetch_page)
            with open(path) as f:
                written = json.load(f)
        self.assertEqual([m["id"] for m in written["data"]], ["a", "b"])
        self.assertEqual(calls, [0, 1])


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd scripts && python3 -m unittest test_cloudtemple_model_report -v`
Expected: FAIL — `cloudtemple-model-report.py` doesn't exist yet (loader error).

- [ ] **Step 3: Write the implementation**

```python
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
```

- [ ] **Step 4: Make it executable and run tests to verify they pass**

Run: `chmod +x scripts/cloudtemple-model-report.py && cd scripts && python3 -m unittest test_cloudtemple_model_report -v`
Expected: PASS (6 tests)

- [ ] **Step 5: Wire both scripts up as flake apps**

Add to `flake.nix`, inside the `apps = { ... };` set (alongside `update-types`/`update-node-modules`):

```nix
update-cloudtemple-models = {
  type = "app";
  program = "${pkgs.writeShellScriptBin "update-cloudtemple-models" ''
    export PATH=${
      lib.makeBinPath [
        pkgs.python3
        pkgs.nixfmt
      ]
    }:$PATH
    exec ${./scripts/fetch-cloudtemple-models.py} "$@"
  ''}/bin/update-cloudtemple-models";
};

cloudtemple-model-report = {
  type = "app";
  program = "${pkgs.writeShellScriptBin "cloudtemple-model-report" ''
    export PATH=${lib.makeBinPath [ pkgs.python3 ]}:$PATH
    exec ${./scripts/cloudtemple-model-report.py} "$@"
  ''}/bin/cloudtemple-model-report";
};
```

- [ ] **Step 6: Smoke-test the apps**

Run: `nix run .#update-cloudtemple-models -- --help && nix run .#cloudtemple-model-report -- --help`
Expected: both print their `argparse` usage/help text and exit 0 (no network needed for `--help`).

- [ ] **Step 7: Commit**

```bash
git add scripts/cloudtemple-model-report.py scripts/test_cloudtemple_model_report.py flake.nix
git commit -m "feat: add cloudtemple-model-report.py and wire both scripts as flake apps"
```

---

### Task 7: `enrichWithLLMaaS` + `vanilla-dev-llmaas`

**Files:**
- Modify: `lib/mkHarness.nix` (add `enrichWithLLMaaS`, make the returned attrset `rec`)
- Modify: `lib/default.nix` (export `enrichWithLLMaaS`)
- Modify: `harnesses/vanilla-dev.nix` (build and export the `llmaas` sibling)
- Modify: `flake.nix` (packages/devShells/checks for `vanilla-dev-llmaas`)

**Interfaces:**
- Consumes: `harnesses/parts/cloud-temple.nix`, `harnesses/parts/cloud-temple-agents.nix` (Tasks 3-4), `mkHarness`, `defaultWrapArgs` (existing, same file).
- Produces: `enrichWithLLMaaS :: { name, modules, wrapArgs ? null } -> { package, config, devShell }` (same shape as `mkHarness`'s return, `name` suffixed `-llmaas`).

- [ ] **Step 1: Add `enrichWithLLMaaS` to `lib/mkHarness.nix`**

Change the file's final `in { mkHarness = ...; inherit defaultWrapArgs; }` to `in rec { ... }` and add the new attribute (`mkHarness` and `defaultWrapArgs` must be visible to `enrichWithLLMaaS`, hence `rec`):

```nix
in
rec {
  mkHarness =
    {
      name,
      modules,
      wrapArgs ? null,
    }:
    # ... unchanged body ...
    let
      # (existing body, unchanged)
    in
    {
      inherit package;
      inherit (parts) config;
      devShell = pkgs.mkShell { packages = [ package ]; };
    };
  enrichWithLLMaaS =
    {
      name,
      modules,
      wrapArgs ? null,
    }:
    mkHarness {
      name = "${name}-llmaas";
      modules = modules ++ [
        (import ../harnesses/parts/cloud-temple.nix { })
        (import ../harnesses/parts/cloud-temple-agents.nix { })
      ];
      inherit wrapArgs;
    };
  inherit defaultWrapArgs;
}
```

(Only the closing attrset changes — the existing `mkHarness` body between `let ... in` stays exactly as-is; don't retype it.)

- [ ] **Step 2: Export it from `lib/default.nix`**

```nix
{
  inherit generated domain modules;
  inherit (mkHarnessLib) defaultWrapArgs;
  inherit (modules) evalHarness;
  inherit (mkHarnessLib) mkHarness enrichWithLLMaaS;
}
```

- [ ] **Step 3: Verify it evaluates standalone**

```bash
nix eval --impure --expr '
  let
    pkgs = import <nixpkgs> {};
    nixwrap = builtins.getFlake "github:rti/nixwrap";
    opencode = (builtins.getFlake "github:numtide/llm-agents.nix").packages.${builtins.currentSystem}.opencode;
    harnessLib = import ./lib { inherit (pkgs) lib; inherit pkgs nixwrap opencode; };
  in (harnessLib.enrichWithLLMaaS {
    name = "test";
    modules = [ (import ./harnesses/parts/base.nix { inherit (pkgs) lib; }) ];
  }).config.opencode.provider.cloud-temple.npm
'
```
Expected: `"@ai-sdk/openai-compatible"` (confirms `enrichWithLLMaaS` composes and calls through to `mkHarness` correctly before touching any real harness file).

- [ ] **Step 4: Wire `vanilla-dev-llmaas` into `harnesses/vanilla-dev.nix`**

```nix
{
  lib,
  pkgs,
  nixwrap,
  opencode,
  agent-skills,
  superpowers,
  semble,
}:
let
  harnessLib = import ../lib {
    inherit
      lib
      pkgs
      nixwrap
      opencode
      ;
  };
  modules = [
    (import ./parts/base.nix { inherit lib; })
    (import ./parts/superpowers.nix {
      inherit
        pkgs
        agent-skills
        superpowers
        ;
    })
    (import ./parts/semble.nix { inherit semble; })
    (import ./parts/be-concise.nix)
  ];
  harness = harnessLib.mkHarness {
    name = "vanilla-dev";
    inherit modules;
  };
  llmaasHarness = harnessLib.enrichWithLLMaaS {
    name = "vanilla-dev";
    inherit modules;
  };
in
{
  inherit (harness) package;
  devShell = pkgs.mkShell {
    packages = [ harness.package ];
  };
  llmaas = {
    inherit (llmaasHarness) package;
    devShell = pkgs.mkShell {
      packages = [ llmaasHarness.package ];
    };
  };
}
```

- [ ] **Step 5: Wire `packages`/`devShells`/`checks.vanilla-dev-llmaas` into `flake.nix`**

Next to the existing `packages.vanilla-dev`/`devShells.vanilla-dev`:

```nix
packages.vanilla-dev-llmaas = vanillaDevHarness.llmaas.package;
...
devShells.vanilla-dev-llmaas = vanillaDevHarness.llmaas.devShell;
```

Add a new check next to `checks.vanilla-dev` (same `run()`/`resolv` bwrap helper, copied verbatim):

```nix
vanilla-dev-llmaas =
  pkgs.runCommand "check-vanilla-dev-llmaas"
    {
      nativeBuildInputs = [
        pkgs.bubblewrap
        pkgs.coreutils
        pkgs.bash
        pkgs.jq
        vanillaDevHarness.llmaas.package
      ];
      inherit resolv;
    }
    ''
      set -euo pipefail
      export HOME=$TMPDIR; mkdir -p $HOME

      run() {
        bwrap \
          --die-with-parent \
          --tmpfs / \
          --ro-bind /nix /nix \
          --dir /bin \
          --ro-bind /bin/sh /bin/sh \
          --dir /usr/bin \
          --ro-bind ${pkgs.coreutils}/bin/env /usr/bin/env \
          --ro-bind /etc/passwd /etc/passwd \
          --ro-bind /etc/group /etc/group \
          --ro-bind /etc/hosts /etc/hosts \
          --dir /etc/ssl --dir /etc/static/ssl \
          --ro-bind $resolv /etc/resolv.conf \
          --dir /tmp \
          --proc /proc --dev /dev \
          --bind $TMPDIR $TMPDIR \
          --setenv HOME $TMPDIR \
          --setenv PATH ${
            lib.makeBinPath [
              pkgs.bubblewrap
              pkgs.coreutils
              pkgs.bash
            ]
          } \
          --chdir $TMPDIR \
          -- "$@"
      }

      run ${vanillaDevHarness.llmaas.package}/bin/opencode debug config > config.json
      jq -e '.provider["cloud-temple"].npm == "@ai-sdk/openai-compatible"' config.json >/dev/null
      jq -e '.provider["cloud-temple"].options.baseURL == "https://api.ai.cloud-temple.com/v1"' config.json >/dev/null
      jq -e '.agent.build.model == "cloud-temple/qwen-coder-next:80b"' config.json >/dev/null
      jq -e '.agent.plan.model == "cloud-temple/qwen3.6:35b"' config.json >/dev/null
      jq -e '.agent.general.model == "cloud-temple/qwen3.6:27b"' config.json >/dev/null
      jq -e '.agent["semble-search"].model == "cloud-temple/qwen3.5:9b"' config.json >/dev/null

      echo ok > $out
    '';
```

- [ ] **Step 6: Run the check, fix until it passes**

Run: `git add -A && nix flake check -L --show-trace .#checks.$(nix eval --raw --impure --expr 'builtins.currentSystem').vanilla-dev-llmaas`
Expected: eventually `ok`. If it fails, the printed jq assertion tells you exactly which config key is wrong — fix `cloud-temple.nix`/`cloud-temple-agents.nix`/the wiring, not the check.

- [ ] **Step 7: Commit**

```bash
git add lib/mkHarness.nix lib/default.nix harnesses/vanilla-dev.nix flake.nix
git commit -m "feat: add enrichWithLLMaaS, wire vanilla-dev-llmaas"
```

---

### Task 8: `superpowers-llmaas`

**Files:**
- Modify: `harnesses/superpowers.nix` (build and export the `llmaas` sibling)
- Modify: `flake.nix` (packages/devShells/checks for `superpowers-llmaas`)

**Interfaces:**
- Consumes: `enrichWithLLMaaS` (Task 7).
- Produces: `packages.superpowers-llmaas`, `devShells.superpowers-llmaas`, `checks.superpowers-llmaas`.

- [ ] **Step 1: Wire `superpowers-llmaas` into `harnesses/superpowers.nix`**

```nix
{
  lib,
  pkgs,
  nixwrap,
  opencode,
  agent-skills,
  superpowers,
}:
let
  harnessLib = import ../lib {
    inherit
      lib
      pkgs
      nixwrap
      opencode
      ;
  };
  modules = [
    (import ./parts/base.nix { inherit lib; })
    (import ./parts/superpowers.nix {
      inherit
        pkgs
        agent-skills
        superpowers
        ;
    })
    (import ./parts/test-skill.nix)
    (import ./parts/test-tool.nix)
    (import ./parts/test-agent.nix)
    (import ./parts/test-command.nix)
    (import ./parts/test-rule.nix)
  ];
  harness = harnessLib.mkHarness {
    name = "superpowers";
    inherit modules;
  };
  llmaasHarness = harnessLib.enrichWithLLMaaS {
    name = "superpowers";
    inherit modules;
  };
in
{
  inherit (harness) package;
  devShell = pkgs.mkShell {
    packages = [ harness.package ];
  };
  llmaas = {
    inherit (llmaasHarness) package;
    devShell = pkgs.mkShell {
      packages = [ llmaasHarness.package ];
    };
  };
}
```

- [ ] **Step 2: Wire `packages`/`devShells`/`checks.superpowers-llmaas` into `flake.nix`**

Next to the existing `packages.superpowers`/`devShells.superpowers`:

```nix
packages.superpowers-llmaas = superpowersHarness.llmaas.package;
...
devShells.superpowers-llmaas = superpowersHarness.llmaas.devShell;
```

Add the check (identical structure to Task 7's, targeting `superpowersHarness.llmaas.package`):

```nix
superpowers-llmaas =
  pkgs.runCommand "check-superpowers-llmaas"
    {
      nativeBuildInputs = [
        pkgs.bubblewrap
        pkgs.coreutils
        pkgs.bash
        pkgs.jq
        superpowersHarness.llmaas.package
      ];
      inherit resolv;
    }
    ''
      set -euo pipefail
      export HOME=$TMPDIR; mkdir -p $HOME

      run() {
        bwrap \
          --die-with-parent \
          --tmpfs / \
          --ro-bind /nix /nix \
          --dir /bin \
          --ro-bind /bin/sh /bin/sh \
          --dir /usr/bin \
          --ro-bind ${pkgs.coreutils}/bin/env /usr/bin/env \
          --ro-bind /etc/passwd /etc/passwd \
          --ro-bind /etc/group /etc/group \
          --ro-bind /etc/hosts /etc/hosts \
          --dir /etc/ssl --dir /etc/static/ssl \
          --ro-bind $resolv /etc/resolv.conf \
          --dir /tmp \
          --proc /proc --dev /dev \
          --bind $TMPDIR $TMPDIR \
          --setenv HOME $TMPDIR \
          --setenv PATH ${
            lib.makeBinPath [
              pkgs.bubblewrap
              pkgs.coreutils
              pkgs.bash
            ]
          } \
          --chdir $TMPDIR \
          -- "$@"
      }

      run ${superpowersHarness.llmaas.package}/bin/opencode debug config > config.json
      jq -e '.provider["cloud-temple"].npm == "@ai-sdk/openai-compatible"' config.json >/dev/null
      jq -e '.agent.build.model == "cloud-temple/qwen-coder-next:80b"' config.json >/dev/null
      jq -e '.agent.plan.model == "cloud-temple/qwen3.6:35b"' config.json >/dev/null
      jq -e '.agent.general.model == "cloud-temple/qwen3.6:27b"' config.json >/dev/null

      echo ok > $out
    '';
```

- [ ] **Step 3: Run the check, fix until it passes**

Run: `git add -A && nix flake check -L --show-trace .#checks.$(nix eval --raw --impure --expr 'builtins.currentSystem').superpowers-llmaas`
Expected: `ok`.

- [ ] **Step 4: Commit**

```bash
git add harnesses/superpowers.nix flake.nix
git commit -m "feat: wire superpowers-llmaas"
```

---

### Task 9: Full verification pass

**Files:** none (verification only).

- [ ] **Step 1: Format the whole tree**

Run: `nix fmt`
Expected: reformats any Nix touched across Tasks 3-8 that drifted from canonical style; 0 changes on a second run.

- [ ] **Step 2: Run the full Python test suite**

Run: `cd scripts && python3 -m unittest discover -v`
Expected: all tests from Tasks 1, 2, 5, 6 pass together (import order / `sys.path` clashes would show up here first).

- [ ] **Step 3: Run the full flake check**

Run: `git add -A && nix flake check -L --show-trace`
Expected: every check passes, including the new `vanilla-dev-llmaas`/`superpowers-llmaas` and the pre-existing `plugin-deps-are-current`/`types-are-current`/`superpowers`/`vanilla-dev`/`formatting`.

- [ ] **Step 4: Manually run the report script against real cached data (requires `data/modelgrep-models.json`)**

Run: `nix run .#cloudtemple-model-report -- --fetch`
Expected: prints unmatched Cloud Temple models, per-match metrics, and a proposed mapping. Compare the proposal against Task 4's hand-picked `cloud-temple-agents.nix` values — if the data-backed proposal disagrees, that's expected (Task 4 was a best guess); leave a note for a follow-up but don't change the curated file as part of this plan (spec requires it stay hand-curated).

- [ ] **Step 5: Commit any leftover changes**

`data/modelgrep-models.json` (written by Step 4) and any `nix fmt` reformatting from Step 1 are the only expected leftovers:

```bash
git add -A
git status  # confirm only data/modelgrep-models.json and/or formatting fixes are staged
git commit -m "chore: cache modelgrep ratings, nix fmt after Cloud Temple support"
```
