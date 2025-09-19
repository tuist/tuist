#!/bin/bash
#MISE description="Run Erlang's observer tool on a remote Fly.io instance"

# After opening a Wireguard connection to your Fly network, run this script to
# open a BEAM Observer from your local machine to the remote server. This creates
# a local node that is clustered to a machine running on Fly.

# In order for it to work:
# - Your wireguard connection must be up.
# - The COOKIE value must be the same as the cookie value used for your project.
# - Observer needs to be working in your local environment. That requires WxWidget support in your Erlang install.

# When done, close Observer. It leaves you with an open IEx shell that is connected to the remote server. You can safely CTRL+C, CTRL+C to exit it.

# COOKIE NOTE:
# ============
# You can explicitly set the COOKIE value in the script if you prefer. That would look like this.
#
# COOKIE=YOUR-COOKIE-VALUE

set -e

if [ -z "$COOKIE" ]; then
    echo "Set the COOKIE your project uses in the COOKIE ENV value before running this script."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "jq is not installed. Please install it before running this script. It is a command-line JSON processor."
    exit 1
fi

# Get the data we need in JSON format
json_data=$(flyctl status --json)

# Extract app name
app_name=$(echo "$json_data" | jq -r '.Name')

# Extract private_ip for the first started machine
private_ip=$(echo "$json_data" | jq -r '.Machines[] | select(.state == "started") | .private_ip' | head -n 1)

# Extract image_ref tag hash for the first started machine
image_tags=$(echo "$json_data" | jq -r '.Machines[] | select(.state == "started") | .image_ref.tag | sub("deployment-"; "")' | head -n 1)

if [ -z "$private_ip" ]; then
    echo "No instances appear to be running at this time."
    exit 1
fi

# Assemble the full node name
FULL_NODE_NAME="${app_name}-${image_tags}@${private_ip}"
echo Attempting to connect to $FULL_NODE_NAME

# IMPORTANT:
# ==========
# Fly.io uses an IPv6 network internally for private IPs. The BEAM needs IPv6
# support to be enabled explicitly.
#
# The issue is, if it's enabled globally like in a `.bashrc` file, then setting
# it here essentially flips it OFF. If not set globally, then it should be set
# here. Choose the version that fits your situation.
#
# It's the `--erl "-proto_dist inet6_tcp"` portion.

# Toggles on IPv6 support for the local node being started.
iex --erl "-proto_dist inet6_tcp" --sname my_remote --cookie ${COOKIE} -e "IO.inspect(Node.connect(:'${FULL_NODE_NAME}'), label: \"Node Connected?\"); IO.inspect(Node.list(), label: \"Connected Nodes\"); :observer.start"

# Does NOT toggle on IPv6 support, assuming it is enabled some other way.
# iex --sname my_remote --cookie ${COOKIE} -e "IO.inspect(Node.connect(:'${FULL_NODE_NAME}'), label: \"Node Connected?\"); IO.inspect(Node.list(), label: \"Connected Nodes\"); :observer.start"
