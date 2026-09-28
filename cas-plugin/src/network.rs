//! Whether the machine's network changed under the proxy.
//!
//! The proxy outlives network changes: a laptop joins or leaves a VPN, moves
//! between Wi-Fi networks, or docks. Its HTTP/2 connections can survive the
//! move, still pointing at whichever region the previous network's resolver
//! chose, so the proxy renews them when the set of addresses the machine holds
//! changes. Only a hash of that set is kept, never the addresses themselves.

use std::collections::hash_map::DefaultHasher;
use std::ffi::CStr;
use std::hash::{Hash, Hasher};

/// A hash of the machine's routable interface addresses, or `None` when they
/// cannot be listed. Loopback and link-local addresses are left out: they
/// exist on every network and come and go with interfaces that carry no
/// traffic to the cache.
pub fn fingerprint() -> Option<u64> {
    let mut entries = interface_addresses()?;
    entries.sort();
    entries.dedup();
    let mut hasher = DefaultHasher::new();
    entries.hash(&mut hasher);
    Some(hasher.finish())
}

fn interface_addresses() -> Option<Vec<(String, Vec<u8>)>> {
    let mut head: *mut libc::ifaddrs = std::ptr::null_mut();
    // SAFETY: getifaddrs allocates a list we walk read-only and free below.
    if unsafe { libc::getifaddrs(&mut head) } != 0 {
        return None;
    }
    let mut entries = Vec::new();
    let mut cursor = head;
    while !cursor.is_null() {
        // SAFETY: cursor is a node of the list getifaddrs returned.
        let entry = unsafe { &*cursor };
        cursor = entry.ifa_next;
        let up = entry.ifa_flags & (libc::IFF_UP as libc::c_uint) != 0;
        let loopback = entry.ifa_flags & (libc::IFF_LOOPBACK as libc::c_uint) != 0;
        if !up || loopback || entry.ifa_addr.is_null() || entry.ifa_name.is_null() {
            continue;
        }
        // SAFETY: ifa_addr is non-null and points at a sockaddr of its family.
        let Some(address) = (unsafe { routable_address(entry.ifa_addr) }) else {
            continue;
        };
        // SAFETY: ifa_name is a NUL-terminated interface name.
        let name = unsafe { CStr::from_ptr(entry.ifa_name) }
            .to_string_lossy()
            .into_owned();
        entries.push((name, address));
    }
    // SAFETY: head came from a successful getifaddrs.
    unsafe { libc::freeifaddrs(head) };
    Some(entries)
}

unsafe fn routable_address(address: *const libc::sockaddr) -> Option<Vec<u8>> {
    match i32::from((*address).sa_family) {
        libc::AF_INET => {
            let ipv4 = &*(address as *const libc::sockaddr_in);
            let octets = ipv4.sin_addr.s_addr.to_ne_bytes();
            // 169.254.0.0/16
            (octets[0..2] != [169, 254]).then(|| octets.to_vec())
        }
        libc::AF_INET6 => {
            let ipv6 = &*(address as *const libc::sockaddr_in6);
            let octets = ipv6.sin6_addr.s6_addr;
            // fe80::/10
            let link_local = octets[0] == 0xfe && octets[1] & 0xc0 == 0x80;
            (!link_local).then(|| octets.to_vec())
        }
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn is_stable_while_nothing_changes() {
        let first = fingerprint();
        assert!(first.is_some(), "a test host can list its interfaces");
        assert_eq!(first, fingerprint());
    }
}
