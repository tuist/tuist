use std::{net::IpAddr, time::Duration};

use futures_util::StreamExt;
use reqwest::{
    Url,
    header::{ACCEPT_ENCODING, HeaderMap, LOCATION},
};
use sha2::{Digest as _, Sha256, Sha384, Sha512};
use tokio::io::AsyncWriteExt;
use tonic::Status;

use super::{
    AssetService,
    request::{FetchSpec, validate_url},
};
use crate::{
    artifact::producer::ArtifactProducer,
    constants::MAX_MODULE_TOTAL_BYTES,
    file_cache::{FOREGROUND_FILE_CACHE_DROP_INTERVAL_BYTES, reserve_foreground_staging},
    replication::replication_targets,
    store::StagedArtifactPath,
    utils::{TempFileCleanup, blob_key, drop_staging_cache_range, temp_file_path},
};

impl AssetService {
    async fn open(
        &self,
        mut url: Url,
        mut headers: HeaderMap,
    ) -> Result<reqwest::Response, Status> {
        for redirects in 0..=10 {
            validate_url(&url)?;
            let host = url
                .host_str()
                .expect("validated URL")
                .trim_matches(['[', ']']);
            let port = url.port_or_known_default().expect("HTTP port");
            let addresses = if let Ok(ip) = host.parse::<IpAddr>() {
                vec![std::net::SocketAddr::new(ip, port)]
            } else {
                tokio::net::lookup_host((host, port))
                    .await
                    .map_err(|_| Status::unavailable("asset origin DNS lookup failed"))?
                    .take(32)
                    .collect::<Vec<_>>()
            };
            if addresses.is_empty() {
                return Err(Status::unavailable(
                    "asset origin DNS returned no addresses",
                ));
            }
            for address in &addresses {
                #[cfg(test)]
                if self.allow_loopback && address.ip().is_loopback() {
                    continue;
                }
                if !is_public_ip(address.ip()) {
                    return Err(Status::permission_denied(
                        "asset origin resolves to a non-public address",
                    ));
                }
            }
            // Resolve once, validate, and pin the result to the connection. Automatic redirects,
            // proxies and a second DNS lookup would each bypass the destination check.
            let client = reqwest::Client::builder()
                .no_proxy()
                .redirect(reqwest::redirect::Policy::none())
                .resolve_to_addrs(host, &addresses)
                .connect_timeout(Duration::from_secs(10))
                .read_timeout(Duration::from_secs(30))
                .build()
                .map_err(|_| Status::internal("failed to initialize asset downloader"))?;
            let response = client
                .get(url.clone())
                .headers(headers.clone())
                .header(ACCEPT_ENCODING, "identity")
                .send()
                .await
                .map_err(|_| Status::unavailable("asset origin connection failed"))?;
            if matches!(response.status().as_u16(), 301 | 302 | 303 | 307 | 308) {
                if redirects == 10 {
                    return Err(Status::aborted("asset origin exceeded the redirect limit"));
                }
                let next = response
                    .headers()
                    .get(LOCATION)
                    .and_then(|v| v.to_str().ok())
                    .and_then(|v| url.join(v).ok())
                    .ok_or_else(|| Status::aborted("asset origin returned an invalid redirect"))?;
                if url.scheme() == "https" && next.scheme() != "https" {
                    return Err(Status::permission_denied(
                        "asset redirect would downgrade HTTPS",
                    ));
                }
                if url.origin() != next.origin() {
                    headers.clear();
                }
                url = next;
                continue;
            }
            return match response.status().as_u16() {
                200 => Ok(response),
                401 | 403 => Err(Status::permission_denied(
                    "asset origin denied the download",
                )),
                404 | 410 => Err(Status::not_found(
                    "asset origin did not contain the requested file",
                )),
                408 | 429 | 500 | 502 | 503 | 504 => Err(Status::unavailable(
                    "asset origin is temporarily unavailable",
                )),
                _ => Err(Status::aborted(
                    "asset origin returned an unexpected HTTP status",
                )),
            };
        }
        unreachable!("redirect loop is bounded")
    }

    pub(super) async fn download(
        &self,
        spec: &FetchSpec,
        index: usize,
        namespace: &str,
    ) -> Result<
        (
            bazel_remote_apis::build::bazel::remote::execution::v2::Digest,
            bool,
        ),
        Status,
    > {
        let state = &self.reapi.state;
        let response = self
            .open(spec.uris[index].clone(), spec.headers[index].clone())
            .await?;
        let declared = response.content_length();
        if declared.is_some_and(|n| n > MAX_MODULE_TOTAL_BYTES) {
            return Err(Status::resource_exhausted(
                "asset exceeds the 2 GiB blob limit",
            ));
        }
        let memory =
            reserve_foreground_staging(&state.memory, declared.unwrap_or(MAX_MODULE_TOTAL_BYTES))
                .await
                .map_err(|_| Status::resource_exhausted("asset staging memory is exhausted"))?;
        let policy = memory.file_cache_policy();
        let disk = state
            .tmp_staging_budget
            .try_reserve(declared.unwrap_or(0))
            .map_err(|_| Status::resource_exhausted("asset temporary storage is exhausted"))?;
        let path = temp_file_path(&state.config.tmp_dir, "remote-asset");
        let mut cleanup = TempFileCleanup::new(path.clone(), disk);
        state
            .io
            .create_dir_all(&state.config.tmp_dir)
            .await
            .map_err(Status::internal)?;
        let mut file = state
            .io
            .create_file(&path)
            .await
            .map_err(Status::internal)?;
        let mut stream = response.bytes_stream();
        let (mut sha256, mut sha384, mut sha512) = (Sha256::new(), Sha384::new(), Sha512::new());
        let mut size = 0_u64;
        let mut advised = 0_u64;
        while let Some(chunk) = stream.next().await {
            let chunk = chunk.map_err(|_| Status::unavailable("asset body transfer failed"))?;
            size = size.saturating_add(chunk.len() as u64);
            if size > MAX_MODULE_TOTAL_BYTES {
                return Err(Status::resource_exhausted(
                    "asset exceeds the 2 GiB blob limit",
                ));
            }
            cleanup
                .grow_reservation_to(size)
                .map_err(|_| Status::resource_exhausted("asset temporary storage is exhausted"))?;
            sha256.update(&chunk);
            sha384.update(&chunk);
            sha512.update(&chunk);
            file.write_all(&chunk)
                .await
                .map_err(|_| Status::internal("failed to stage asset bytes"))?;
            if policy.should_drop(
                state.memory.should_reclaim_file_cache(),
                state.memory.transient_reserved_bytes(),
            ) && size.saturating_sub(advised) >= FOREGROUND_FILE_CACHE_DROP_INTERVAL_BYTES
            {
                file = drop_staging_cache_range(file, &path, advised, size - advised, &state.io)
                    .await
                    .map_err(Status::internal)?;
                advised = size;
            }
        }
        if declared.is_some_and(|declared| declared != size) {
            return Err(Status::unavailable(
                "asset body length did not match Content-Length",
            ));
        }
        if spec
            .checksum
            .as_ref()
            .is_some_and(|checksum| !checksum.matches(&sha256, &sha384, &sha512))
        {
            return Err(Status::aborted("asset bytes did not match checksum.sri"));
        }
        file.flush()
            .await
            .map_err(|_| Status::internal("failed to flush asset bytes"))?;
        drop(file);
        let digest = bazel_remote_apis::build::bazel::remote::execution::v2::Digest {
            hash: hex::encode(sha256.finalize()),
            size_bytes: size as i64,
        };
        let key = blob_key(&format!("{}/{}", digest.hash, size));
        let persisted = state
            .store
            .persist_artifact_from_path_and_enqueue(
                ArtifactProducer::Reapi,
                namespace,
                &key,
                "application/octet-stream",
                StagedArtifactPath::new(&path, policy),
                &replication_targets(state),
            )
            .await
            .map_err(|error| {
                if crate::store::is_outbox_full_error(&error) {
                    Status::resource_exhausted("replication backlog is full")
                } else {
                    Status::internal("failed to store downloaded asset")
                }
            })?;
        cleanup.remove_and_disarm(&state.io).await;
        state.notify.notify_one();
        state
            .metrics
            .record_artifact_write(ArtifactProducer::Reapi, "ok", size);
        Ok((digest, !persisted.already_present))
    }
}

fn is_public_ip(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(ip) => {
            let [a, b, c, _] = ip.octets();
            !(matches!(a, 0 | 10 | 127 | 224..=255)
                || (a == 100 && (64..=127).contains(&b))
                || (a == 169 && b == 254)
                || (a == 172 && (16..=31).contains(&b))
                || (a == 192
                    && (b == 168 || (b == 0 && matches!(c, 0 | 2)) || (b == 88 && c == 99)))
                || (a == 198 && (matches!(b, 18 | 19) || (b == 51 && c == 100)))
                || (a == 203 && b == 0 && c == 113))
        }
        IpAddr::V6(ip) => {
            if let Some(ip) = ip.to_ipv4_mapped() {
                return is_public_ip(IpAddr::V4(ip));
            }
            let [a, b, ..] = ip.segments();
            (a & 0xe000) == 0x2000
                && !(a == 0x2001 && (b < 0x0200 || b == 0x0db8))
                && a != 0x2002
                && a != 0x3fff
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn blocks_non_public_destinations_including_ipv4_mapped_ipv6() {
        for ip in [
            "0.0.0.0",
            "10.1.2.3",
            "100.100.100.200",
            "127.0.0.1",
            "169.254.169.254",
            "172.16.0.1",
            "192.168.0.1",
            "192.0.0.1",
            "198.19.0.1",
            "224.0.0.1",
            "255.255.255.255",
            "::",
            "::1",
            "fc00::1",
            "fe80::1",
            "ff02::1",
            "::ffff:127.0.0.1",
            "64:ff9b::a00:1",
            "2002:7f00:1::",
            "2001:db8::1",
        ] {
            assert!(!is_public_ip(ip.parse().unwrap()), "{ip}");
        }
        for ip in [
            "1.1.1.1",
            "8.8.8.8",
            "185.199.108.133",
            "2606:4700:4700::1111",
        ] {
            assert!(is_public_ip(ip.parse().unwrap()), "{ip}");
        }
    }
}
