#!/usr/bin/env python3
# SPDX-License-Identifier: CC0-1.0
"""Recomputes the compose hash dstack measures for a program of this folder.

    python3 compose-hash.py ../v3/docker-compose.yml
    python3 compose-hash.py ../v3/docker-compose.yml prelaunch-ours.sh
    python3 compose-hash.py ../v5/docker-compose.yml prelaunch-ours.sh --allow PHALA_AI_API_KEY

The compose hash is the SHA-256 of the manifest (app-compose.json) that Phala Cloud builds
from the compose file, a pre-launch script (its default one unless another is given) and
its default settings. The settings
below are those of our runs of 16 November 2026 (Phala KMS, public logs, no environment
variable accepted unless named with --allow: an encrypted secret the machine may receive,
whose name, not value, is measured). Another setting, or another version of the pre-launch
script, gives another hash.
"""
import hashlib
import json
import pathlib
import sys

here = pathlib.Path(__file__).parent
args = sys.argv[1:]
allowed = []
while "--allow" in args:
    i = args.index("--allow")
    allowed.append(args[i + 1])
    del args[i:i + 2]
read = lambda path: pathlib.Path(path).read_bytes().decode("utf-8")

manifest = {
    "allowed_envs": sorted(allowed),
    "docker_compose_file": read(args[0]),
    "features": ["kms", "tproxy-net"],
    "gateway_enabled": True,
    "kms_enabled": True,
    "local_key_provider_enabled": False,
    "manifest_version": 2,
    "name": "",
    "no_instance_id": False,
    "pre_launch_script": read(args[1] if len(args) > 1 else here / "prelaunch.sh"),
    "public_logs": True,
    "public_sysinfo": True,
    "public_tcbinfo": True,
    "runner": "docker-compose",
    "secure_time": False,
    "storage_fs": "ext4",
    "tproxy_enabled": True,
}
raw = json.dumps(manifest, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
compose_hash = hashlib.sha256(raw).hexdigest()
print("manifest bytes:", len(raw))
print("compose hash:  ", compose_hash)
print("MRCONFIGID:    ", "01" + compose_hash + "00" * 15)
