#!/bin/sh
# Run inside a Kata container given /dev/kvm: proves the guest kernel's KVM
# works for an unprivileged user by creating a VM, which is the first thing
# an emulator does.
set -eu
echo "guest kernel $(uname -r), $(grep -cE 'vmx|svm' /proc/cpuinfo) vCPUs with vmx/svm"
ls -l /dev/kvm
for user in root nobody; do
  su -s /bin/sh "$user" -c 'perl -e '"'"'
    open(my $kvm, "+<", "/dev/kvm") or die "open /dev/kvm: $!\n";
    my $api = ioctl($kvm, 0xAE00, 0);   # KVM_GET_API_VERSION
    defined $api or die "KVM_GET_API_VERSION: $!\n";
    defined ioctl($kvm, 0xAE01, 0) or die "KVM_CREATE_VM: $!\n";
    printf "%s: KVM API %d, created a VM\n", scalar getpwuid($<), $api;
  '"'"''
done
