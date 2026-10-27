#!/bin/sh
# Run inside a Kata container given /dev/kvm: proves the guest kernel's KVM
# works for an unprivileged user by doing what an emulator's QEMU does first:
# create a VM, its in-kernel interrupt controller, and a vCPU.
set -eu
echo "guest kernel $(uname -r), $(grep -cE 'vmx|svm' /proc/cpuinfo) vCPUs with vmx/svm"
ls -l /dev/kvm
for user in root nobody; do
  su -s /bin/sh "$user" -c 'perl -e '"'"'
    open(my $kvm, "+<", "/dev/kvm") or die "open /dev/kvm: $!\n";
    my $api = ioctl($kvm, 0xAE00, 0);   # KVM_GET_API_VERSION
    defined $api or die "KVM_GET_API_VERSION: $!\n";
    my $fd = ioctl($kvm, 0xAE01, 0);    # KVM_CREATE_VM
    defined $fd or die "KVM_CREATE_VM: $!\n";
    open(my $vm, "+<&=", $fd + 0) or die "open VM fd: $!\n";
    defined ioctl($vm, 0xAE60, 0) or die "KVM_CREATE_IRQCHIP: $!\n";
    defined ioctl($vm, 0xAE41, 0) or die "KVM_CREATE_VCPU: $!\n";
    printf "%s: KVM API %d, created a VM, its irqchip and a vCPU\n", scalar getpwuid($<), $api;
  '"'"''
done
