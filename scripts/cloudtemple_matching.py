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
