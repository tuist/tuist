#!/usr/bin/env bash
# Contains the affected CAs inside a disposable macOS Tart guest whose admin
# password is `admin`. Shared by the runner and xcresult processor Packer
# templates, which upload it beside pem-store.sh, policy.json and the controls.
set -euo pipefail

security find-certificate -a -p /System/Library/Keychains/SystemRootCertificates.keychain > /tmp/tuist-system-roots.pem
bash /tmp/tuist-pem-store.sh extract-blocked /tmp/tuist-system-roots.pem /tmp/tuist-blocked-cas
openssl verify -CAfile /tmp/tuist-issuer-roots.pem /tmp/tuist-negative-intermediate.pem
if security verify-cert -c /tmp/tuist-negative-intermediate.pem -p basic -R offline >/dev/null 2>&1; then echo 'Native negative-chain baseline: trusted before containment'; else echo 'Native negative-chain baseline: already rejected; no differential containment claim'; fi
echo 'admin' | sudo -S true
# SIP protects this authorization rule on current macOS. Authenticate
# the disposable guest's admin instead of rewriting the rule to allow.
echo 'admin' | security authorize -C admin com.apple.trust-settings.admin
for cert in /tmp/tuist-blocked-cas/*.pem; do [ -e "$cert" ] || continue; sudo security add-trusted-cert -d -r deny -k /Library/Keychains/System.keychain "$cert"; if security verify-cert -c "$cert" -p basic >/dev/null 2>&1; then echo 'Native verifier accepted a denied root' >&2; exit 1; fi; done
if security verify-cert -c /tmp/tuist-negative-intermediate.pem -p basic -R offline >/dev/null 2>&1; then echo 'Native verifier accepted a compromised intermediate chain' >&2; exit 1; fi
security verify-cert -c /tmp/tuist-positive-root.pem -p basic -R offline
bash /tmp/tuist-pem-store.sh filter /etc/ssl/cert.pem /tmp/tuist-cacerts.pem
bash /tmp/tuist-pem-store.sh check /tmp/tuist-cacerts.pem
echo 'admin' | sudo -S install -m 0644 /tmp/tuist-cacerts.pem /etc/ssl/cert.pem
rm /tmp/tuist-cacerts.pem
/opt/homebrew/bin/brew update
HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1 /opt/homebrew/bin/brew upgrade ca-certificates
bash /tmp/tuist-pem-store.sh filter /opt/homebrew/etc/ca-certificates/cert.pem /tmp/tuist-homebrew-roots.pem
sudo install -m 0644 /tmp/tuist-homebrew-roots.pem /opt/homebrew/etc/ca-certificates/cert.pem
bash /tmp/tuist-pem-store.sh check /etc/ssl/cert.pem /opt/homebrew/etc/ca-certificates/cert.pem
rm -f /tmp/tuist-negative-intermediate.pem /tmp/tuist-issuer-roots.pem /tmp/tuist-positive-root.pem /tmp/tuist-system-roots.pem /tmp/tuist-homebrew-roots.pem
rm -rf /tmp/tuist-blocked-cas
