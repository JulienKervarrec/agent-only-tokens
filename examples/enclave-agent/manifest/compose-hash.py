#!/usr/bin/env python3
# SPDX-License-Identifier: CC0-1.0
"""Recomputes the compose hash dstack measures for a program of this folder.

    python3 compose-hash.py ../v3/docker-compose.yml
    python3 compose-hash.py ../v3/docker-compose.yml prelaunch-ours.sh

The compose hash is the SHA-256 of the manifest (app-compose.json) that Phala Cloud builds
from the compose file, a pre-launch script (its default one unless another is given) and
its default settings. The settings
below are those of our runs of 16 November 2026 (Phala KMS, public logs, no environment
variable accepted). Another setting, or another version of the pre-launch script, gives
another hash.
"""
import hashlib
import json
import pathlib
import sys

here = pathlib.Path(__file__).parent
read = lambda path: pathlib.Path(path).read_bytes().decode("utf-8")

manifest = {
    "allowed_envs": [],
    "docker_compose_file": read(sys.argv[1]),
    "features": ["kms", "tproxy-net"],
    "gateway_enabled": True,
    "kms_enabled": True,
    "local_key_provider_enabled": False,
    "manifest_version": 2,
    "name": "",
    "no_instance_id": False,
    "pre_launch_script": read(sys.argv[2] if len(sys.argv) > 2 else here / "prelaunch.sh"),
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
