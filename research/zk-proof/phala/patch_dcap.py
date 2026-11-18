"""Make Automata's dcap-rs build outside its workspace: fixed package fields, no dev-dependencies."""
import sys

path = sys.argv[1]
s = open(path).read()
s = s.replace('license = { workspace = true }', 'license = "MIT"')
s = s.replace('version = { workspace = true }', 'version = "1.1.0"')
s = s.replace('edition = { workspace = true }', 'edition = "2021"')
s = s[: s.index("[dev-dependencies]")] + s[s.index("[features]"):]
open(path, "w").write(s)
