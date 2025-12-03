#!/bin/bash
set -e

# Configuration
RUNNER_VERSION="2.330.0"
VM_IMAGE="ghcr.io/tuist/macos:26.1-xcode-26.1.1"
SSH_USER="${VM_SSH_USER:-tuist}"
SSH_KEY="${VM_SSH_KEY_PATH:-~/.ssh/id_ed25519}"
RUNNER_PATH="/opt/actions-runner"

echo "=== GitHub Actions Runner Update Script ==="
echo "Runner version: $RUNNER_VERSION"
echo "VM image: $VM_IMAGE"
echo "SSH user: $SSH_USER"
echo "SSH key: $SSH_KEY"
echo ""

# Create a container from the image (persistent, not ephemeral)
echo "Creating container from image '$VM_IMAGE'..."
CONTAINER_ID=$(curie create "$VM_IMAGE" 2>&1 | grep -oE '[a-f0-9]{12}' | head -1)

if [ -z "$CONTAINER_ID" ]; then
    echo "ERROR: Failed to create container"
    exit 1
fi

echo "Container ID: $CONTAINER_ID"

# Start the container
echo "Starting container..."
curie start "$CONTAINER_ID" --no-window &
START_PID=$!

# Wait for VM to boot
echo "Waiting for VM to boot..."
sleep 30

# Get VM IP
echo "Getting VM IP address..."
for i in {1..30}; do
    VM_IP=$(curie inspect "$CONTAINER_ID" -f json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('arp',[{}])[0].get('ip',''))" 2>/dev/null || echo "")
    if [ -n "$VM_IP" ] && [ "$VM_IP" != "" ]; then
        echo "VM IP: $VM_IP"
        break
    fi
    echo "Waiting for IP... (attempt $i/30)"
    sleep 5
done

if [ -z "$VM_IP" ]; then
    echo "ERROR: Failed to get VM IP address"
    kill $START_PID 2>/dev/null || true
    curie rm "$CONTAINER_ID" 2>/dev/null || true
    exit 1
fi

# Wait for SSH to be ready
echo "Waiting for SSH to be ready..."
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -i $SSH_KEY"

for i in {1..30}; do
    if ssh $SSH_OPTS "$SSH_USER@$VM_IP" "echo SSH ready" 2>/dev/null; then
        echo "SSH is ready!"
        break
    fi
    echo "Waiting for SSH... (attempt $i/30)"
    sleep 5
done

# Update the runner
echo ""
echo "=== Updating GitHub Actions Runner to v$RUNNER_VERSION ==="
ssh $SSH_OPTS "$SSH_USER@$VM_IP" bash -s << EOF
set -e
cd $RUNNER_PATH

echo "Current runner version:"
./config.sh --version 2>/dev/null || cat .runner 2>/dev/null || echo "Unknown"

echo ""
echo "Downloading runner v$RUNNER_VERSION..."
curl -sL -o actions-runner.tar.gz "https://github.com/actions/runner/releases/download/v$RUNNER_VERSION/actions-runner-osx-arm64-$RUNNER_VERSION.tar.gz"

echo "Extracting..."
tar xzf actions-runner.tar.gz

echo "Cleaning up..."
rm -f actions-runner.tar.gz

echo ""
echo "New runner version:"
./config.sh --version 2>/dev/null || echo "Installation complete"
EOF

echo ""
echo "=== Shutting down VM ==="
ssh $SSH_OPTS "$SSH_USER@$VM_IP" "sudo shutdown -h now" 2>/dev/null || true

# Wait for VM to shut down
echo "Waiting for VM to shut down..."
sleep 15

# Kill the start process if still running
kill $START_PID 2>/dev/null || true

echo ""
echo "=== Committing changes to image ==="
echo "Committing container $CONTAINER_ID to $VM_IMAGE..."
curie commit "$CONTAINER_ID" "$VM_IMAGE"

echo ""
echo "=== Cleaning up container ==="
curie rm "$CONTAINER_ID" 2>/dev/null || true

echo ""
echo "=== Done! ==="
echo ""
echo "The image '$VM_IMAGE' has been updated with GitHub Actions runner v$RUNNER_VERSION."
echo ""
echo "To push the updated image to the registry:"
echo "  curie push $VM_IMAGE"
