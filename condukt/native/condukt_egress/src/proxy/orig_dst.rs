//! Recover the original destination of a redirected connection via
//! `SO_ORIGINAL_DST`. Linux-only; on other platforms we fall back to the
//! socket's local address so the dev/test build stays usable.

use std::io;
use std::net::SocketAddr;

#[cfg(target_os = "linux")]
pub fn original_dst(socket: &tokio::net::TcpStream) -> io::Result<SocketAddr> {
    use std::mem;
    use std::net::{Ipv4Addr, SocketAddrV4};
    use std::os::fd::AsRawFd;

    let fd = socket.as_raw_fd();

    let mut addr: libc::sockaddr_in = unsafe { mem::zeroed() };
    let mut len = mem::size_of::<libc::sockaddr_in>() as libc::socklen_t;

    // SOL_IP = 0, SO_ORIGINAL_DST = 80 (defined in linux/netfilter_ipv4.h).
    const SO_ORIGINAL_DST: libc::c_int = 80;

    let rc = unsafe {
        libc::getsockopt(
            fd,
            libc::SOL_IP,
            SO_ORIGINAL_DST,
            &mut addr as *mut _ as *mut libc::c_void,
            &mut len,
        )
    };

    if rc != 0 {
        return Err(io::Error::last_os_error());
    }

    let port = u16::from_be(addr.sin_port);
    let ip = u32::from_be(addr.sin_addr.s_addr);
    let ip = Ipv4Addr::from(ip);

    Ok(SocketAddr::V4(SocketAddrV4::new(ip, port)))
}

#[cfg(not(target_os = "linux"))]
pub fn original_dst(socket: &tokio::net::TcpStream) -> io::Result<SocketAddr> {
    // Dev fallback for macOS/Windows: there is no netfilter redirect on
    // these platforms, so we cannot recover an original destination. We
    // return the local address so unit tests and ad-hoc smoke tests have
    // something to bind on; in real K8s deployments this code path is
    // not reached because the sidecar runs on Linux.
    socket.local_addr()
}
