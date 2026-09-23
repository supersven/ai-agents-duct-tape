#!/usr/bin/env python3
"""Generate lib/types/generated.nix from opencode config.json.

Usage: generate-types.py <config.json> <output.nix>
"""
import json
import re
import subprocess
import sys

IDENT = re.compile(r"^[a-zA-Z_][a-zA-Z0-9_'-]*$")


def nix_attr(name: str) -> str:
    """Quote attr name if not a bare Nix identifier."""
    return name if IDENT.match(name) else nix_str(name)


def nix_str(s: str) -> str:
    """Escape a string as a Nix double-quoted string literal.

    Nix has no Unicode escape sequence: string literals are byte strings,
    so non-ASCII characters must be emitted raw (UTF-8). Only `"`, `\\`,
    `${`, and the `\\n`/`\\r`/`\\t` escapes are interpreted by Nix.
    """
    out = ['"']
    i = 0
    while i < len(s):
        ch = s[i]
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "$" and i + 1 < len(s) and s[i + 1] == "{":
            out.append("\\${")
            i += 1
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\t":
            out.append("\\t")
        elif ch == "\r":
            out.append("\\r")
        else:
            out.append(ch)
        i += 1
    out.append('"')
    return "".join(out)


def nix_literal(v) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, str):
        return nix_str(v)
    if isinstance(v, (int, float)):
        return str(v)
    raise ValueError(f"unsupported literal: {v!r}")


class Gen:
    def __init__(self, schema: dict):
        self.defs = schema["$defs"]
        self.root = schema.get("$ref", "#/$defs/Config").rsplit("/", 1)[-1]

    def type_ref(self, ref: str) -> str:
        if ref.startswith("#/$defs/"):
            return f"generatedTypes.{nix_attr(ref.split('/')[-1])}"
        return "lib.types.str"  # external (models.dev)

    def type_expr(self, node: dict, ind: int = 0) -> str:
        if "$ref" in node:
            return self.type_ref(node["$ref"])
        if "enum" in node:
            vals = " ".join(nix_literal(v) for v in node["enum"])
            return f"lib.types.enum [ {vals} ]"
        t = node.get("type")
        if t == "string":
            return "lib.types.str"
        if t == "integer":
            return self.bounded("lib.types.int", node)
        if t == "number":
            return self.bounded("lib.types.float", node)
        if t == "boolean":
            return "lib.types.bool"
        if t == "array":
            if "prefixItems" in node:
                inner = " ".join(f"({self.type_expr(i, ind)})" for i in node["prefixItems"])
                return f"lib.types.listOf (lib.types.oneOf [ {inner} ])"
            items = node.get("items")
            if items:
                return f"lib.types.listOf ({self.type_expr(items, ind)})"
            return "lib.types.listOf lib.types.anything"
        if t == "object":
            return self.object_expr(node, ind)
        if "anyOf" in node:
            inner = " ".join(f"({self.type_expr(b, ind)})" for b in node["anyOf"])
            return f"lib.types.oneOf [ {inner} ]"
        if "oneOf" in node:
            inner = " ".join(f"({self.type_expr(b, ind)})" for b in node["oneOf"])
            return f"lib.types.oneOf [ {inner} ]"
        return "lib.types.anything"

    def bounded(self, base: str, node: dict) -> str:
        checks = []
        for k, op in (("minimum", ">="), ("maximum", "<="),
                      ("exclusiveMinimum", ">"), ("exclusiveMaximum", "<")):
            if k in node:
                checks.append(f"x {op} {node[k]}")
        if not checks:
            return base
        pred = "x: " + " && ".join(checks)
        return f"(lib.types.addCheck {base} ({pred}))"

    def object_expr(self, node: dict, ind: int = 0) -> str:
        p = "  " * ind
        props = node.get("properties", {})
        ap = node.get("additionalProperties")
        if not props:
            if isinstance(ap, dict):
                return f"lib.types.attrsOf ({self.type_expr(ap, ind)})"
            return "lib.types.attrs"
        lines = [f"{p}lib.types.submodule {{", f"{p}  options = {{"]
        for name, sub in props.items():
            lines.append(f"{p}    {nix_attr(name)} = {self.mkoption(sub, ind + 3)};")
        lines.append(f"{p}  }};")
        if isinstance(ap, dict):
            lines.append(f"{p}  freeformType = lib.types.attrsOf ({self.type_expr(ap, ind + 1)});")
        lines.append(f"{p}}}")
        return "\n".join(lines)

    def mkoption(self, node: dict, ind: int) -> str:
        p = "  " * ind
        desc = node.get("description")
        d = f"{p}    description = {nix_str(desc)};\n" if isinstance(desc, str) else ""
        return (
            p + "mkOption {\n"
            + f"{p}    type = lib.types.nullOr ({self.type_expr(node, ind)});\n"
            + f"{p}    default = null;\n"
            + d
            + p + "  }"
        )

    def root_options(self) -> str:
        root = self.defs[self.root]
        props = root.get("properties", {})
        lines = ["{"]
        for name, sub in props.items():
            lines.append(f"  {nix_attr(name)} = {self.mkoption(sub, 1)};")
        lines.append("}")
        return "\n".join(lines)

    def def_expr(self, name: str) -> str:
        if name == self.root:
            root = self.defs[self.root]
            ap = root.get("additionalProperties")
            free = f"\n      freeformType = lib.types.attrsOf ({self.type_expr(ap, 3)});" if isinstance(ap, dict) else ""
            return f"lib.types.submodule {{\n      options = options.{nix_attr(self.root)};{free}\n    }}"
        return self.type_expr(self.defs[name], 2)

    def generate(self) -> str:
        out = [
            "{ lib }:",
            "let",
            "  mkOption = lib.mkOption;",
            "  options = {",
            f"    {nix_attr(self.root)} = {self.root_options()};",
            "  };",
            "  generatedTypes = {",
        ]
        for name in self.defs:
            out.append(f"    {nix_attr(name)} = {self.def_expr(name)};")
        out.append("  };")
        out.append("in")
        out.append("{")
        out.append("  inherit generatedTypes options;")
        out.append("  types = generatedTypes;")
        out.append("}")
        return "\n".join(out) + "\n"


def nixfmt(s: str) -> str:
    """Format Nix source with nixfmt-rfc-style (must be in PATH)."""
    try:
        res = subprocess.run(
            ["nixfmt"], input=s, text=True, capture_output=True, check=True
        )
        return res.stdout
    except (OSError, subprocess.CalledProcessError) as e:
        stderr = getattr(e, "stderr", None)
        detail = f": {stderr}" if stderr else ""
        sys.exit(f"error: nixfmt failed: {e}{detail}")


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit("usage: generate-types.py <config.json> <output.nix>")
    with open(sys.argv[1]) as f:
        schema = json.load(f)
    with open(sys.argv[2], "w") as f:
        f.write(nixfmt(Gen(schema).generate()))


if __name__ == "__main__":
    main()
