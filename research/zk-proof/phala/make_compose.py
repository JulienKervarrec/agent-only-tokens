"""Write docker-compose.yml for the Phala machine: our sources travel inside it (BUNDLE)."""
import base64
import io
import os
import tarfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILES = ["Cargo.toml", "src/main.rs", "fetch_collateral.py", "phala/patch_dcap.py", "phala/run.sh"]

buf = io.BytesIO()
with tarfile.open(fileobj=buf, mode="w:gz") as t:
    for f in FILES:
        info = t.gettarinfo(os.path.join(ROOT, f), arcname=os.path.basename(f) if f.startswith("phala/") else f)
        info.uid = info.gid = 0
        info.uname = info.gname = ""
        info.mtime = 0
        with open(os.path.join(ROOT, f), "rb") as fh:
            t.addfile(info, fh)
bundle = base64.b64encode(buf.getvalue()).decode()

# QUOTE_URL (optional): a running agent's answer to prove instead of the published quote.
quote_url = f'\n      QUOTE_URL: "{os.environ["QUOTE_URL"]}"' if os.environ.get("QUOTE_URL") else ""

compose = f"""services:
  prover:
    image: rust:1-bookworm
    working_dir: /data
    environment:
      RISC0_WORK_DIR: aotwork{quote_url}
      BUNDLE: "{bundle}"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - aotwork:/data/aotwork
    ports:
      - "8080:8080"
    command: ["bash", "-c", "mkdir -p /src && echo \\"$$BUNDLE\\" | base64 -d | tar xz -C /src run.sh && bash /src/run.sh"]
    restart: "no"
volumes:
  aotwork:
    name: aotwork
"""
out = os.path.join(ROOT, "phala", "docker-compose.yml")
open(out, "w").write(compose)
print(out, len(compose), "bytes")
