# Agent-Only Tokens: the pre-launch script, in place of Phala Cloud's default one.
# dstack runs it before the program and measures it with the rest of the manifest.
# It does nothing: no registry login, no image pull, no root password, no SSH key,
# no file from the host, no environment variable. The program's image is pinned by
# digest, and dstack pulls it when it starts the compose file.
echo "Agent-Only Tokens: no pre-launch step"
