//! TLS and environment CONNECT-proxy configuration for the native REAPI client.
use base64::Engine as _;
use eyre::{Result, bail};
use std::{io, sync::Arc, time::Duration};
use tokio::{
    io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt},
    net::TcpStream,
};
use tonic::transport::{Channel, Endpoint};
use url::Url;

trait Connection: AsyncRead + AsyncWrite + Unpin + Send {}
impl<T: AsyncRead + AsyncWrite + Unpin + Send> Connection for T {}

fn proxy(endpoint: &Url, variables: impl Fn(&str) -> Option<String>) -> Result<Option<Url>> {
    if variables("TUIST_CARGO_CACHE_USE_ENVIRONMENT_PROXY").as_deref() == Some("false") {
        return Ok(None);
    }
    let host = endpoint
        .host_str()
        .unwrap_or_default()
        .trim_matches(['[', ']'])
        .to_lowercase();
    let authority = format!("{host}:{}", endpoint.port_or_known_default().unwrap_or(443));
    for entry in variables("NO_PROXY")
        .or_else(|| variables("no_proxy"))
        .unwrap_or_default()
        .split(',')
    {
        let entry = entry.trim().to_lowercase();
        if entry == "*"
            || entry == host
            || entry == authority
            || (!entry.contains(':')
                && !entry.is_empty()
                && (host == entry.trim_start_matches('.')
                    || host.ends_with(&format!(".{}", entry.trim_start_matches('.')))))
        {
            return Ok(None);
        }
    }
    let keys: &[&str] = if endpoint.scheme() == "https" {
        &["HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy"]
    } else {
        &["HTTP_PROXY", "http_proxy"]
    };
    let Some(value) = keys
        .iter()
        .find_map(|key| variables(key).filter(|v| !v.is_empty()))
    else {
        return Ok(None);
    };
    let value = Url::parse(&value)?;
    if !matches!(value.scheme(), "http" | "https") || value.host_str().is_none() {
        bail!("unsupported REAPI CONNECT proxy");
    }
    Ok(Some(value))
}

async fn proxy_connection(
    proxy: Url,
    authority: String,
) -> io::Result<hyper_util::rt::TokioIo<Box<dyn Connection>>> {
    let host = proxy
        .host_str()
        .ok_or_else(|| io::Error::other("proxy host missing"))?;
    let host = host.trim_matches(['[', ']']);
    let tcp = TcpStream::connect((host, proxy.port_or_known_default().unwrap_or(80))).await?;
    let mut connection: Box<dyn Connection> = if proxy.scheme() == "https" {
        let mut roots = tokio_rustls::rustls::RootCertStore::empty();
        for certificate in rustls_native_certs::load_native_certs().certs {
            let _ = roots.add(certificate);
        }
        if let Some(path) = ca_certificate_path() {
            let bytes = tokio::fs::read(path).await?;
            let certs: Vec<_> =
                rustls_pemfile::certs(&mut bytes.as_slice()).collect::<io::Result<_>>()?;
            if certs.is_empty() {
                roots
                    .add(tokio_rustls::rustls::pki_types::CertificateDer::from(bytes))
                    .map_err(io::Error::other)?;
            } else {
                for certificate in certs {
                    roots.add(certificate).map_err(io::Error::other)?;
                }
            }
        }
        let config = tokio_rustls::rustls::ClientConfig::builder()
            .with_root_certificates(roots)
            .with_no_client_auth();
        let name = tokio_rustls::rustls::pki_types::ServerName::try_from(host.to_owned())
            .map_err(io::Error::other)?;
        Box::new(
            tokio_rustls::TlsConnector::from(Arc::new(config))
                .connect(name, tcp)
                .await?,
        )
    } else {
        Box::new(tcp)
    };
    let mut request = format!("CONNECT {authority} HTTP/1.1\r\nHost: {authority}\r\n");
    if !proxy.username().is_empty() {
        let user = percent_decode(proxy.username())?;
        let password = percent_decode(proxy.password().unwrap_or_default())?;
        let credential =
            base64::engine::general_purpose::STANDARD.encode(format!("{user}:{password}"));
        request.push_str(&format!("Proxy-Authorization: Basic {credential}\r\n"));
    }
    connection
        .write_all(format!("{request}\r\n").as_bytes())
        .await?;
    connection.flush().await?;
    let mut response = Vec::new();
    while !response.ends_with(b"\r\n\r\n") {
        if response.len() >= 16 * 1024 {
            return Err(io::Error::other("proxy response exceeds limit"));
        }
        let mut byte = [0u8; 1];
        connection.read_exact(&mut byte).await?;
        response.push(byte[0]);
    }
    if !response.starts_with(b"HTTP/1.1 200 ") && !response.starts_with(b"HTTP/1.0 200 ") {
        return Err(io::Error::other("proxy rejected CONNECT"));
    }
    Ok(hyper_util::rt::TokioIo::new(connection))
}

fn percent_decode(value: &str) -> io::Result<String> {
    let bytes = value.as_bytes();
    let mut output = Vec::new();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' {
            if i + 2 >= bytes.len() {
                return Err(io::Error::other("invalid proxy credentials"));
            }
            let value = std::str::from_utf8(&bytes[i + 1..i + 3])
                .ok()
                .and_then(|v| u8::from_str_radix(v, 16).ok())
                .ok_or_else(|| io::Error::other("invalid proxy credentials"))?;
            output.push(value);
            i += 3;
        } else {
            output.push(bytes[i]);
            i += 1;
        }
    }
    String::from_utf8(output).map_err(io::Error::other)
}

pub(crate) fn ca_certificate_path() -> Option<std::ffi::OsString> {
    std::env::var_os("TUIST_CARGO_CACHE_CA_CERTIFICATE")
        .or_else(|| std::env::var_os("TUIST_CA_CERTIFICATE"))
}

pub(crate) fn certificate_pem(bytes: Vec<u8>) -> Vec<u8> {
    if bytes.starts_with(b"-----BEGIN") {
        return bytes;
    }
    format!(
        "-----BEGIN CERTIFICATE-----\n{}\n-----END CERTIFICATE-----\n",
        base64::engine::general_purpose::STANDARD.encode(bytes)
    )
    .into_bytes()
}

pub(crate) async fn connect(endpoint: Endpoint, url: &Url, timeout: Duration) -> Result<Channel> {
    let Some(proxy) = proxy(url, |key| std::env::var(key).ok())? else {
        return Ok(endpoint.connect().await?);
    };
    let host = url.host_str().unwrap_or_default().trim_matches(['[', ']']);
    let authority = if host.contains(':') {
        format!("[{host}]:{}", url.port_or_known_default().unwrap_or(443))
    } else {
        format!("{host}:{}", url.port_or_known_default().unwrap_or(443))
    };
    let connector = tower::service_fn(move |_| {
        let proxy = proxy.clone();
        let authority = authority.clone();
        async move {
            tokio::time::timeout(timeout, proxy_connection(proxy, authority))
                .await
                .map_err(io::Error::other)?
        }
    });
    Ok(endpoint.connect_with_connector(connector).await?)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn connect_proxy_authenticates_and_preserves_tunnel_bytes() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let server = tokio::spawn(async move {
            let (mut stream, _) = listener.accept().await.unwrap();
            let mut headers = Vec::new();
            while !headers.ends_with(b"\r\n\r\n") {
                let mut byte = [0u8; 1];
                stream.read_exact(&mut byte).await.unwrap();
                headers.push(byte[0]);
            }
            let headers = String::from_utf8(headers).unwrap();
            assert!(headers.starts_with("CONNECT cache.example.com:443 HTTP/1.1\r\n"));
            assert!(headers.contains("Proxy-Authorization: Basic dXNlcjpwYXNz\r\n"));
            stream
                .write_all(b"HTTP/1.1 200 Connection established\r\n\r\npong")
                .await
                .unwrap();
        });
        let proxy = Url::parse(&format!("http://user:pass@{address}")).unwrap();
        let tunnel = tokio::time::timeout(
            Duration::from_secs(3),
            proxy_connection(proxy, "cache.example.com:443".into()),
        )
        .await
        .unwrap()
        .unwrap();
        let mut connection = tunnel.into_inner();
        let mut bytes = [0u8; 4];
        connection.read_exact(&mut bytes).await.unwrap();
        assert_eq!(&bytes, b"pong");
        server.await.unwrap();
    }

    #[test]
    fn proxy_settings_and_bypass_do_not_change_target_identity() {
        let endpoint = Url::parse("https://cache.example.com").unwrap();
        let proxy_url = "https://user:password@proxy.example.com:8443/";
        let environment = |key: &str| match key {
            "HTTPS_PROXY" => Some(proxy_url.into()),
            _ => None,
        };
        assert_eq!(
            proxy(&endpoint, environment).unwrap().unwrap().as_str(),
            proxy_url
        );
        assert!(
            proxy(&endpoint, |key| match key {
                "HTTPS_PROXY" => Some(proxy_url.into()),
                "NO_PROXY" => Some(".example.com".into()),
                _ => None,
            })
            .unwrap()
            .is_none()
        );
        assert!(
            proxy(&endpoint, |key| match key {
                "HTTPS_PROXY" => Some(proxy_url.into()),
                "TUIST_CARGO_CACHE_USE_ENVIRONMENT_PROXY" => Some("false".into()),
                _ => None,
            })
            .unwrap()
            .is_none()
        );
        assert_eq!(percent_decode("some%40user").unwrap(), "some@user");
        assert!(percent_decode("%GG").is_err());
    }
}
