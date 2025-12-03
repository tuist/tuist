# VM Setup Guide for Tuist Runners

This guide documents how to create, configure, and distribute macOS VM images for running GitHub Actions jobs in isolated environments using Curie.

## Prerequisites

- Apple Silicon Mac (M1, M2, M3, M4)
- macOS 13.0 or later
- At least 100GB free disk space
- Apple Developer account (for downloading Xcode)
- AWS CLI configured for Tigris (for image distribution)

## 1. Install Curie

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/macvmio/curie/refs/heads/main/.mise/tasks/install)"
```

Verify installation:
```bash
curie --version
```

## 2. Create Base VM Image

### 2.1 Download macOS Restore Image

```bash
curie download -p ~/Downloads/RestoreImage.ipsw
```

This downloads the latest macOS restore image (~15GB).

### 2.2 Build the Base Image

```bash
curie build tuist/runner/xcode-26.1.1:1.0 -i ~/Downloads/RestoreImage.ipsw -d "100 GB"
```

Parameters:
- `tuist/runner/xcode-26.1.1:1.0` - Image name and tag
- `-i` - Path to the IPSW restore image
- `-d "100 GB"` - Disk size (Xcode + simulators need ~60GB)

### 2.3 Start the VM for Configuration

```bash
curie create tuist/runner/xcode-26.1.1:1.0
curie start <container-id>
```

Or run interactively:
```bash
curie run tuist/runner/xcode-26.1.1:1.0 --name setup-vm
```

## 3. Configure the VM

Once the VM boots, complete the macOS setup wizard, then configure:

### 3.1 Enable SSH

1. Open **System Settings** > **General** > **Sharing**
2. Enable **Remote Login**
3. Note the IP address shown

### 3.2 Set Up SSH Key Authentication

On your **host machine**, generate an SSH key:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/tuist_runner_vm_key -N ""
```

Copy the public key to the VM:

```bash
# Get VM IP
VM_IP=$(curie inspect setup-vm -f json | jq -r '.network.ip // .ip // .ipAddress')

# Copy public key (you'll need to enter password)
ssh-copy-id -i ~/.ssh/tuist_runner_vm_key.pub admin@$VM_IP
```

Or manually add the key inside the VM:

```bash
# Inside the VM
mkdir -p ~/.ssh
chmod 700 ~/.ssh
echo "YOUR_PUBLIC_KEY_HERE" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

### 3.3 Install Xcode

Install the `xcodes` tool:

```bash
brew install xcodesorg/made/xcodes
```

Install Xcode 26.1.1:

```bash
xcodes install 26.1.1
```

You'll be prompted for your Apple ID credentials.

Accept the license:

```bash
sudo xcodebuild -license accept
```

### 3.4 Install iOS Simulators (Optional)

```bash
xcodebuild -downloadPlatform iOS
```

### 3.5 Install GitHub Actions Runner

```bash
# Create directory
sudo mkdir -p /opt/actions-runner
sudo chown $(whoami) /opt/actions-runner
cd /opt/actions-runner

# Download latest runner (check https://github.com/actions/runner/releases)
RUNNER_VERSION="2.330.0"
curl -o actions-runner.tar.gz -L "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-osx-arm64-${RUNNER_VERSION}.tar.gz"

# Extract
tar xzf actions-runner.tar.gz
rm actions-runner.tar.gz

# Verify
./run.sh --version
```

### 3.6 Install Additional Tools (Optional)

```bash
# Homebrew (if not already installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Common iOS development tools
brew install cocoapods fastlane swiftlint swiftformat
```

### 3.7 Optimize VM Settings

Disable unnecessary services to improve performance:

```bash
# Disable Spotlight indexing
sudo mdutil -a -i off

# Disable sleep
sudo pmset -a sleep 0
sudo pmset -a hibernatemode 0
sudo pmset -a disablesleep 1
```

## 4. Save the Image

Stop the VM to save changes:

```bash
curie stop setup-vm
```

The image `tuist/runner/xcode-26.1.1:1.0` now contains all your configurations.

## 5. Image Distribution

### 5.1 Set Up Curie Plugins for Tigris

Create the plugin directory:

```bash
mkdir -p ~/.curie/plugins
```

Create the **push** plugin (`~/.curie/plugins/push`):

```bash
#!/bin/bash
set -e

REFERENCE="$2"
TIGRIS_BUCKET="tuist-vm-images"
TIGRIS_ENDPOINT="https://fly.storage.tigris.dev"
TEMP_DIR=$(mktemp -d)
FILENAME=$(echo "$REFERENCE" | tr '/:' '-').zip

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

echo "Exporting $REFERENCE..."
curie export "$REFERENCE" -p "${TEMP_DIR}/${FILENAME}" -c

echo "Uploading to Tigris..."
AWS_ENDPOINT_URL="$TIGRIS_ENDPOINT" aws s3 cp \
    "${TEMP_DIR}/${FILENAME}" \
    "s3://${TIGRIS_BUCKET}/${FILENAME}" \
    --no-progress

echo "Done: ${TIGRIS_ENDPOINT}/${TIGRIS_BUCKET}/${FILENAME}"
```

Create the **pull** plugin (`~/.curie/plugins/pull`):

```bash
#!/bin/bash
set -e

REFERENCE="$2"
TIGRIS_BUCKET="tuist-vm-images"
TIGRIS_ENDPOINT="https://fly.storage.tigris.dev"
TEMP_DIR=$(mktemp -d)
FILENAME=$(echo "$REFERENCE" | tr '/:' '-').zip

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

echo "Downloading $REFERENCE from Tigris..."
AWS_ENDPOINT_URL="$TIGRIS_ENDPOINT" aws s3 cp \
    "s3://${TIGRIS_BUCKET}/${FILENAME}" \
    "${TEMP_DIR}/${FILENAME}" \
    --no-progress

echo "Importing image..."
curie import "$REFERENCE" -p "${TEMP_DIR}/${FILENAME}"

echo "Done: $REFERENCE imported successfully"
```

Make plugins executable:

```bash
chmod +x ~/.curie/plugins/push ~/.curie/plugins/pull
```

### 5.2 Configure Tigris Credentials

Ensure AWS CLI is configured with Tigris credentials:

```bash
# Option 1: Environment variables
export AWS_ACCESS_KEY_ID="your-tigris-access-key"
export AWS_SECRET_ACCESS_KEY="your-tigris-secret-key"

# Option 2: AWS credentials file (~/.aws/credentials)
[default]
aws_access_key_id = your-tigris-access-key
aws_secret_access_key = your-tigris-secret-key
```

### 5.3 Push Image to Tigris

```bash
curie push tuist/runner/xcode-26.1.1:1.0
```

This will:
1. Export the image to a compressed zip file
2. Upload to the Tigris bucket
3. Clean up temporary files

### 5.4 Pull Image on Another Machine

On a new runner machine:

1. Install Curie (see step 1)
2. Set up the plugins (see step 5.1)
3. Configure Tigris credentials (see step 5.2)
4. Pull the image:

```bash
curie pull tuist/runner/xcode-26.1.1:1.0
```

### 5.5 Verify Image

```bash
curie images
```

You should see `tuist/runner/xcode-26.1.1:1.0` in the list.

## 6. Runner Configuration

Set environment variables for the runner:

```bash
export VM_IMAGE="tuist/runner/xcode-26.1.1:1.0"
export VM_SSH_USER="admin"
export VM_SSH_KEY_PATH="~/.ssh/tuist_runner_vm_key"
```

Copy the SSH private key to each runner machine:

```bash
# On the source machine
scp ~/.ssh/tuist_runner_vm_key runner-host:~/.ssh/
ssh runner-host "chmod 600 ~/.ssh/tuist_runner_vm_key"
```

## 7. Image Naming Convention

Follow this naming convention for images:

```
tuist/runner/<xcode-version>:<image-version>
```

Examples:
- `tuist/runner/xcode-26.1.1:1.0` - Xcode 26.1.1, first image version
- `tuist/runner/xcode-26.1.1:1.1` - Xcode 26.1.1, updated image
- `tuist/runner/xcode-26.2:1.0` - Xcode 26.2, first image version

## 8. Updating Images

When you need to update an image (e.g., new Xcode version, security patches):

1. Create a new container from the existing image:
   ```bash
   curie create tuist/runner/xcode-26.1.1:1.0 --name update-vm
   curie start update-vm
   ```

2. Make your changes inside the VM

3. Stop and commit changes:
   ```bash
   curie stop update-vm
   ```

4. Tag with new version:
   ```bash
   curie clone tuist/runner/xcode-26.1.1:1.0 tuist/runner/xcode-26.1.1:1.1
   ```

5. Push the updated image:
   ```bash
   curie push tuist/runner/xcode-26.1.1:1.1
   ```

6. Update `VM_IMAGE` environment variable on runners

## 9. Troubleshooting

### VM won't start
```bash
# Check available images
curie images

# Check running containers
curie ps

# Check system resources
vm_stat
```

### SSH connection fails
```bash
# Verify VM is running and has IP
curie inspect <container-name> -f json | jq '.network'

# Test SSH manually
ssh -i ~/.ssh/tuist_runner_vm_key -o StrictHostKeyChecking=no admin@<vm-ip> "echo ok"
```

### Image pull fails
```bash
# Check Tigris connectivity
AWS_ENDPOINT_URL="https://fly.storage.tigris.dev" aws s3 ls s3://tuist-vm-images/

# Check available space
df -h
```

### Xcode installation issues
```bash
# Check xcodes auth status
xcodes signout
xcodes install 26.1.1  # Re-authenticate

# Manual download alternative
# Download from developer.apple.com and use:
xcodes install --path ~/Downloads/Xcode_26.1.1.xip
```

## 10. Security Considerations

- **SSH Keys**: Keep private keys secure. Consider using separate keys per runner.
- **Apple ID**: Use a dedicated Apple ID for Xcode downloads, not personal accounts.
- **Tigris Access**: Use scoped credentials with minimal permissions.
- **VM Isolation**: Each job runs in an ephemeral VM that's destroyed after completion.
- **Image Updates**: Regularly update images with security patches.
