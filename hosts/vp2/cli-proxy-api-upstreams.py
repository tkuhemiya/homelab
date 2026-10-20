#!/usr/bin/env python3
"""Print CLIProxyAPI's `api-keys:` config section, with model lists fetched live.

Providers come from cli-proxy-api-providers.json. A provider is included only when
its key's environment variable is set, so run this under `doppler run --`.

- gemini: CLIProxyAPI knows Gemini's models itself; only the key is needed.
- openai-compatibility: CLIProxyAPI routes only models listed in its config, so
  this asks the provider's /models endpoint and lists every model that matches
  `include` and doesn't match `exclude` (both regexes, optional). Clients call a
  short alias: "nvidia/nemotron-3-super-120b-a12b:free" -> "nemotron-3-super-120b-a12b".

Exits non-zero if an enabled provider can't be reached, so a network blip never
replaces a working config with one that has no models.
"""
import json
import os
import re
import sys
import urllib.request
from pathlib import Path

q = json.dumps  # a JSON string is a valid YAML string


def fetch_models(base_url, key):
    req = urllib.request.Request(
        base_url.rstrip("/") + "/models",
        # Groq's edge returns 403 to urllib's default "Python-urllib" user agent.
        headers={"Authorization": f"Bearer {key}", "User-Agent": "homelab-cli-proxy-api/1"},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return sorted(m["id"] for m in json.load(resp)["data"])


def alias(model_id):
    return model_id.split("/")[-1].removesuffix(":free")


providers = json.loads((Path(__file__).parent / "cli-proxy-api-providers.json").read_text())
gemini, compat = [], []

for p in providers:
    key = os.environ.get(p["key_env"])
    if not key:
        continue
    if p["type"] == "gemini":
        gemini += [f"    - name: {q(p['name'])}", "      keys:", f"        - api-key: {q(key)}"]
        continue

    try:
        ids = fetch_models(p["base_url"], key)
    except Exception as e:
        sys.exit(f"{p['name']}: can't list models at {p['base_url']}: {e}")
    ids = [
        i for i in ids
        if re.search(p.get("include", ""), i) and not (p.get("exclude") and re.search(p["exclude"], i))
    ]
    if not ids:
        print(f"{p['name']}: no models match the filter, skipping", file=sys.stderr)
        continue

    compat += [
        f"    - name: {q(p['name'])}",
        f"      base-url: {q(p['base_url'])}",
        "      keys:",
        f"        - api-key: {q(key)}",
        "      models:",
    ]
    for i in ids:
        compat += [f"        - name: {q(i)}", f"          alias: {q(alias(i))}"]
    print(f"{p['name']}: {len(ids)} models", file=sys.stderr)

if gemini or compat:
    print("api-keys:")
    if gemini:
        print("  gemini:", *gemini, sep="\n")
    if compat:
        print("  openai-compatibility:", *compat, sep="\n")
