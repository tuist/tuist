# Tuist Runners: Mac Host Setup Guide

This guide covers how to prepare a fresh macOS machine to act as a Tuist Runner host for GitHub Actions workflows.

## Prerequisites

- macOS 12.0 or later (Apple Silicon recommended: M1/M2/M3/M4)
- Static IP address or reliable hostname
- Network access to GitHub.com
- Administrator access to the machine

## 1. Initial macOS Configuration

### 1.1 Set Computer Name

```bash
sudo scutil --set ComputerName "tuist-runner-01"
sudo scutil --set LocalHostName "tuist-runner-01"
sudo scutil --set HostName "tuist-runner-01"
```

### 1.2 Disable Sleep

The runner host must stay awake to accept jobs:

```bash
# Disable sleep entirely
sudo pmset -a sleep 0
sudo pmset -a displaysleep 0
sudo pmset -a disksleep 0

# Disable automatic restart on power failure (optional)
sudo pmset -a autorestart 0
```

### 1.3 Enable Auto-Login (Optional but Recommended)

For headless operation, configure automatic login:

1. Open System Settings → Users & Groups
2. Click "Automatically log in as: [username]"
3. Enter password when prompted

**Security Note:** Only enable auto-login on physically secure machines in trusted networks.

## 2. Create Runner User

Create a dedicated user for running GitHub Actions:

```bash
# Create user (replace with your preferred username)
sudo dscl . -create /Users/admin
sudo dscl . -create /Users/admin UserShell /bin/bash
sudo dscl . -create /Users/admin RealName "Tuist Runner Admin"
sudo dscl . -create /Users/admin UniqueID 1001
sudo dscl . -create /Users/admin PrimaryGroupID 20
sudo dscl . -create /Users/admin NFSHomeDirectory /Users/admin

# Set password
sudo dscl . -passwd /Users/admin

# Add to admin group (if needed for software installation)
sudo dscl . -append /Groups/admin GroupMembership admin

# Create home directory
sudo createhomedir -c -u admin
```

**Note:** The default SSH user in the Tuist orchestrator is `admin`. If you use a different username, you'll need to configure it via environment variable: `TUIST_RUNNERS_SSH_USER=yourusername`

## 3. SSH Configuration

### 3.1 Enable SSH Access

```bash
# Enable Remote Login (SSH)
sudo systemsetup -setremotelogin on

# Verify it's enabled
sudo systemsetup -getremotelogin
```

### 3.2 Generate SSH Key for Orchestrator

On your **local machine** (not the Mac host or Tuist server), generate an SSH key pair:

```bash
# Generate SSH key pair
ssh-keygen -t ed25519 -f ./tuist_runners_id_ed25519 -C "tuist-runners-orchestrator" -N ""

# Display the private key (you'll add this to secrets)
cat ./tuist_runners_id_ed25519

# Display the public key (you'll add this to the Mac host)
cat ./tuist_runners_id_ed25519.pub
```

The private key will be stored in Tuist's encrypted secrets system (see Section 3.4).

### 3.3 Install Public Key on Mac Host

Copy the public key to the Mac host:

```bash
# From your local machine, copy public key to Mac host
ssh-copy-id -i ./tuist_runners_id_ed25519.pub admin@<MAC_HOST_IP>

# Or manually:
# 1. Copy the contents of tuist_runners_id_ed25519.pub
# 2. SSH to Mac host: ssh admin@<MAC_HOST_IP>
# 3. On Mac host, append to ~/.ssh/authorized_keys:
mkdir -p ~/.ssh
chmod 700 ~/.ssh
echo "<PUBLIC_KEY_CONTENT>" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

On the **Mac host**, ensure proper permissions:

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

### 3.4 Configure SSH Keys in Tuist Secrets

Add the SSH private key to your Tuist secrets configuration:

**Option 1: Environment Variable (for testing)**

```bash
# Set the private key as an environment variable
export TUIST_RUNNERS_SSH_PRIVATE_KEY="$(cat ./tuist_runners_id_ed25519)"

# Optionally set a custom SSH user (defaults to "admin")
export TUIST_RUNNERS_SSH_USER="admin"
```

**Option 2: Encrypted Secrets (recommended for production)**

Edit your secrets file (e.g., `priv/secrets/dev.yml` or `priv/secrets/prod.yml.enc`):

```yaml
runners:
  ssh_private_key: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    <your private key content here>
    -----END OPENSSH PRIVATE KEY-----
  ssh_public_key: "ssh-ed25519 AAAAC3Nza... tuist-runners-orchestrator"
  ssh_user: "admin"  # optional, defaults to "admin"
```

For production, encrypt the secrets:

```bash
# Encrypt secrets for production
bin/rails credentials:edit --environment production
```

### 3.5 Test SSH Connection

From your local machine (test with the same key that will be used by Tuist):

```bash
ssh -i ./tuist_runners_id_ed25519 admin@<MAC_HOST_IP> "echo 'SSH connection successful'"
```

### 3.6 Configure SSH Server (Optional Security Hardening)

Edit `/etc/ssh/sshd_config` on the Mac host:

```bash
sudo nano /etc/ssh/sshd_config
```

Recommended settings:

```
# Disable password authentication (key-only)
PasswordAuthentication no
ChallengeResponseAuthentication no

# Disable root login
PermitRootLogin no

# Only allow specific users
AllowUsers admin

# Set idle timeout (30 minutes)
ClientAliveInterval 300
ClientAliveCountMax 3
```

Restart SSH:

```bash
sudo launchctl stop com.openssh.sshd
sudo launchctl start com.openssh.sshd
```

## 4. Install Development Tools

### 4.1 Install Xcode

Install Xcode from the App Store or download from Apple Developer portal.

```bash
# Install Xcode Command Line Tools
sudo xcode-select --install

# Accept license
sudo xcodebuild -license accept

# Verify installation
xcodebuild -version
```

### 4.2 Install Additional Xcode Versions (Optional)

For projects requiring multiple Xcode versions:

```bash
# Download additional Xcode versions from developer.apple.com
# Install to /Applications/Xcode_15.0.app, /Applications/Xcode_14.3.app, etc.

# List installed Xcode versions
sudo xcode-select --print-path
ls /Applications/Xcode*.app
```

**Note:** Tuist Runners currently spawns runners using the default Xcode. For multi-version support, you'll need to configure runners with specific labels and modify the spawn script to select the appropriate Xcode.

### 4.3 Install Homebrew

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Add to PATH (for non-interactive shells)
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.bashrc
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zshrc
```

### 4.4 Install Common Dependencies

```bash
brew install git
brew install node
brew install ruby
brew install fastlane

# Install CocoaPods (if needed)
sudo gem install cocoapods
```

## 5. Configure Runner Environment

### 5.1 Create Runner Working Directory

```bash
# Create base directory for runner installations
mkdir -p ~/runners
cd ~/runners
```

**Note:** The Tuist orchestrator will create subdirectories like `~/actions-runner-tuist-runner-abc123def` for each job. Ensure sufficient disk space (recommend 50GB+ free).

### 5.2 Set Environment Variables (Optional)

Add to `~/.bashrc` or `~/.zshrc`:

```bash
# GitHub Actions runner configuration
export RUNNER_ALLOW_RUNASROOT=0

# Set path for Homebrew, CocoaPods, etc.
export PATH="/opt/homebrew/bin:$PATH"
export PATH="/usr/local/bin:$PATH"
```

## 6. Network Configuration

### 6.1 Configure Firewall

```bash
# Enable firewall
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on

# Allow SSH
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add /usr/libexec/sshd-keygen-wrapper
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp /usr/libexec/sshd-keygen-wrapper

# Check status
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
```

### 6.2 Static IP Configuration (Recommended)

Configure a static IP for reliable orchestrator access:

1. Open System Settings → Network
2. Select your network interface
3. Click "Details"
4. Go to TCP/IP tab
5. Set "Configure IPv4" to "Manually"
6. Enter IP address, subnet mask, and router

Alternatively, configure a DHCP reservation on your router.

### 6.3 DNS Configuration

Ensure the host can resolve GitHub.com:

```bash
# Test DNS resolution
nslookup github.com
ping -c 3 github.com

# Test HTTPS connectivity
curl -I https://github.com
```

## 7. System Resource Verification

### 7.1 Check Available Resources

```bash
# Check CPU info
sysctl -n machdep.cpu.brand_string
sysctl -n hw.ncpu

# Check RAM
sysctl -n hw.memsize | awk '{print $0/1024/1024/1024 " GB"}'

# Check disk space
df -h /

# Check system info
system_profiler SPHardwareDataType
```

### 7.2 Recommended Specifications

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | M1 (8-core) | M2 Pro/Max or M4 |
| RAM | 16 GB | 32 GB+ |
| Storage | 256 GB SSD | 512 GB+ SSD |
| Network | 100 Mbps | 1 Gbps |

### 7.3 Set Runner Capacity

The **capacity** value (number of concurrent jobs) should be based on:

- **CPU cores**: 1-2 jobs per 4 cores
- **RAM**: Minimum 8GB per concurrent job
- **Disk I/O**: Consider SSD performance

**Examples:**
- Mac Mini M1 (8-core, 16GB): capacity = 2
- Mac Studio M2 Max (12-core, 32GB): capacity = 4
- Mac Studio M2 Ultra (24-core, 64GB): capacity = 6

## 8. Register Host with Tuist Orchestrator

Once the Mac host is configured, register it with the Tuist server.

### 8.1 Gather Host Information

```bash
# Get IP address
ipconfig getifaddr en0  # or en1 for Ethernet

# Get hostname
hostname

# Note your SSH port (usually 22)
```

### 8.2 Register via Database (Temporary)

Until management UI/CLI is available, register via direct database insert or `iex`:

```elixir
# Start Elixir shell on Tuist server
iex -S mix

# Register the host
alias Tuist.Runners

{:ok, host} = Runners.create_runner_host(%{
  name: "tuist-runner-01",
  ip: "192.168.1.100",
  ssh_port: 22,
  capacity: 2,
  status: :online,
  chip_type: :m1,  # or :m2, :m3, :m4, :intel
  ram_gb: 16,
  storage_gb: 256
})
```

### 8.3 Verify Registration

```elixir
# List all hosts
Runners.list_runner_hosts()

# Check available hosts
Runners.get_available_hosts()
```

## 9. Verification & Testing

### 9.1 Test SSH from Orchestrator

Verify SSH connectivity using the same key configured in secrets:

```bash
# Test basic SSH
ssh -i ./tuist_runners_id_ed25519 admin@192.168.1.100 "echo 'Connection OK'"

# Test runner process check (should return "not_running" initially)
ssh -i ./tuist_runners_id_ed25519 admin@192.168.1.100 \
  "pgrep -f 'Runner.Listener' > /dev/null && echo 'running' || echo 'not_running'"

# Test directory creation
ssh -i ./tuist_runners_id_ed25519 admin@192.168.1.100 \
  "mkdir -p ~/test-runner && ls -la ~/test-runner"
```

**Note:** The Tuist orchestrator will load the SSH key from secrets at runtime and write it to a temporary location for SSH connections.

### 9.2 Test GitHub Actions Runner Installation

Manually test runner installation on the host:

```bash
# On Mac host
cd ~
mkdir -p actions-runner-test
cd actions-runner-test

# Download runner (adjust version as needed)
curl -o actions-runner-osx-arm64.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.321.0/actions-runner-osx-arm64-2.321.0.tar.gz

# Extract
tar xzf actions-runner-osx-arm64.tar.gz

# Verify files
ls -la
```

### 9.3 Monitor System Resources

```bash
# Monitor CPU/Memory during test runs
top -l 1 | head -n 10

# Monitor disk usage
df -h

# Monitor running processes
ps aux | grep Runner
```

## 10. Maintenance & Monitoring

### 10.1 Log Monitoring

Monitor runner logs:

```bash
# View recent runner logs
ls -lt ~/actions-runner-*/runner.log | head -5
tail -f ~/actions-runner-tuist-runner-*/runner.log
```

### 10.2 Cleanup Old Runners

The orchestrator handles cleanup, but verify manually:

```bash
# List runner directories
ls -la ~ | grep actions-runner-

# Check for orphaned processes
ps aux | grep Runner.Listener

# Manual cleanup if needed (be careful!)
# pkill -f Runner.Listener
# rm -rf ~/actions-runner-*
```

### 10.3 System Updates

```bash
# Check for macOS updates (schedule during maintenance windows)
softwareupdate --list

# Update Homebrew packages
brew update && brew upgrade

# Update Xcode (via App Store)
```

### 10.4 Disk Space Management

```bash
# Check disk usage
df -h
du -sh ~/runners/*
du -sh ~/Library/Developer/Xcode/DerivedData

# Clean Xcode derived data (if space is low)
rm -rf ~/Library/Developer/Xcode/DerivedData/*
```

## 11. Troubleshooting

### SSH Connection Issues

```bash
# Verify SSH is running
sudo launchctl list | grep ssh

# Check SSH logs
log show --predicate 'process == "sshd"' --last 1h

# Test from Mac host
ssh localhost
```

### Runner Process Issues

```bash
# Check if runner is stuck
ps aux | grep Runner.Listener

# Kill stuck runner
pkill -f Runner.Listener

# Check for disk space
df -h
```

### Network Issues

```bash
# Test GitHub connectivity
curl -v https://api.github.com

# Check DNS
scutil --dns

# Check network settings
networksetup -listallnetworkservices
```

### Xcode Issues

```bash
# Verify active Xcode
xcode-select -p

# Switch Xcode version
sudo xcode-select -s /Applications/Xcode.app

# Clear Xcode cache
rm -rf ~/Library/Developer/Xcode/DerivedData
rm -rf ~/Library/Caches/com.apple.dt.Xcode
```

## 12. Security Considerations

### 12.1 Physical Security

- Keep the Mac in a locked room or secure location
- Use cable locks for physical theft prevention
- Consider using FileVault disk encryption

### 12.2 Network Security

- Place runners on isolated VLAN if possible
- Use firewall rules to restrict access to SSH port
- Consider VPN for orchestrator-to-runner communication
- Regularly review SSH authorized_keys file

### 12.3 Access Control

- Use strong SSH key passphrases (stored in orchestrator)
- Rotate SSH keys periodically (every 90 days)
- Monitor SSH access logs for suspicious activity
- Disable password authentication completely

### 12.4 Software Security

- Keep macOS updated (schedule maintenance windows)
- Keep Xcode updated
- Regularly update Homebrew packages
- Monitor for security advisories

## 13. Next Steps

After completing this setup:

1. **Register the host** with Tuist orchestrator (see Section 8.2)
2. **Enable runners** for your GitHub organization
3. **Create a test workflow** with `runs-on: [tuist-runners]` label
4. **Monitor the first job** execution via Tuist server logs
5. **Document any issues** and iterate on configuration

## References

- [GitHub Actions Self-hosted Runners Documentation](https://docs.github.com/en/actions/hosting-your-own-runners)
- [macOS SSH Configuration](https://support.apple.com/guide/mac-help/allow-a-remote-computer-to-access-your-mac-mchlp1066/mac)
- [Xcode Command Line Tools](https://developer.apple.com/xcode/)
