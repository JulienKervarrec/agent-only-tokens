# The measured manifest, rebuilt

dstack does not measure the compose file alone. It measures a manifest
(`app-compose.json`) that Phala Cloud builds from the compose file, its default
pre-launch script and its settings. The compose hash is the SHA-256 of that
manifest.

| File | What it is |
| --- | --- |
| `prelaunch.sh` | Phala Cloud's default pre-launch script, version 0.0.21, unchanged. From [Dstack-TEE/dstack-examples](https://github.com/Dstack-TEE/dstack-examples/blob/3811c903df9643b68d5510b0a63828384ab2c1c3/phala-cloud-prelaunch-script/prelaunch.sh), commit `3811c90`. Apache License 2.0, see `LICENSE-prelaunch`. SHA-256 `c452d7122315255914858880fa3d7931f965f57d04631ead4b7164736bcd0765` |
| `LICENSE-prelaunch` | The licence of that script. The rest of this repository is CC0 |
| `compose-hash.py` | Rebuilds the manifest for a compose file and prints its hash. Python 3, no dependency |

    python3 compose-hash.py ../v3/docker-compose.yml

| Program | Compose hash, as computed here and as measured by the machine |
| --- | --- |
| `../docker-compose.yml` | `95b3c3e50b054db593842d68401d342d36136cd7c6002ecedebcdece9608dc21` |
| `../run-2026-11-16/modified-docker-compose.yml` | `6b79fe2460f3f6464dba5093077a0f0d0d6439e5087f37fd8fbd0097c6271412` |
| `../v2/docker-compose.yml` | `580353bba6700abc63f66733f8b8449afc130eaffaed93153728faa7e8547ef8` |
| `../v3/docker-compose.yml` | `494249cb35c479595b27b20728f8dbd264c68fb84a0a5e17e0c48ad6c5a500a3` |

The first three were measured before this folder existed. The fourth was
computed here first, then found on the machine.

The settings in `compose-hash.py` are those of our runs: Phala KMS, gateway on,
public logs, and no environment variable accepted (`allowed_envs` empty).
Another setting, or another version of the script, gives another hash.
