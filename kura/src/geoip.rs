use std::{io::Read, net::IpAddr, path::Path, sync::RwLock, time::Duration};

use flate2::read::GzDecoder;
use futures_util::StreamExt;
use maxminddb::{Reader, geoip2};
use reqwest::Client;
use time::{Month, OffsetDateTime};

/// Path of the DB-IP Lite City MMDB vendored into the Kura container
/// image. The Dockerfile downloads the monthly dump at build time and
/// drops it here, so the database is always available at startup in
/// official deployments. Self-built images that omit this file degrade
/// gracefully: [`GeoIp::open`] returns `None` and geographic attribution
/// is silently skipped.
pub const GEOIP_DATABASE_PATH: &str = "/opt/geoip/dbip-city-lite.mmdb";

const DBIP_URL_TEMPLATE: &str = "https://download.db-ip.com/free/dbip-city-lite-{ym}.mmdb.gz";
const REFRESH_DOWNLOAD_TIMEOUT: Duration = Duration::from_secs(60);
/// Hard ceiling on the compressed body the refresher will accept from
/// DB-IP. Recent DB-IP Lite City dumps are ~60 MiB compressed; 128 MiB
/// gives ample headroom while keeping refresh memory predictably bounded.
const MAX_COMPRESSED_BYTES: usize = 128 * 1024 * 1024;
/// Hard ceiling on the decompressed payload the refresher will accept.
/// City-level MMDB dumps land around ~125 MiB decompressed today;
/// 256 MiB leaves room for organic growth without unbounded allocation.
const MAX_DECOMPRESSED_BYTES: u64 = 256 * 1024 * 1024;

pub struct GeoIp {
    reader: RwLock<Reader<Vec<u8>>>,
}

/// Coarse geographic location resolved from an IP address. Both fields
/// are best-effort: DB-IP Lite City carries a country for essentially
/// every routable address but only populates `subdivision` for the
/// larger administrative regions, so callers must treat it as optional.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct GeoLocation {
    /// ISO 3166-1 alpha-2 country code, e.g. `US`.
    pub country: Option<String>,
    /// ISO 3166-2 subdivision code, e.g. `US-CA`.
    pub subdivision: Option<String>,
}

#[derive(Debug, Clone, Copy)]
pub enum RefreshOutcome {
    Updated,
    HttpError,
    ParseError,
}

impl RefreshOutcome {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Updated => "ok",
            Self::HttpError => "http_error",
            Self::ParseError => "parse_error",
        }
    }
}

impl GeoIp {
    pub fn open() -> Option<Self> {
        Self::open_at(Path::new(GEOIP_DATABASE_PATH))
    }

    fn open_at(path: &Path) -> Option<Self> {
        match Reader::open_readfile(path) {
            Ok(reader) => Some(Self {
                reader: RwLock::new(reader),
            }),
            Err(error) => {
                tracing::warn!(
                    path = %path.display(),
                    %error,
                    "GeoIP database not loaded; client geographic attribution disabled"
                );
                None
            }
        }
    }

    /// Resolves an IP to its coarse geographic location: the ISO 3166-1
    /// alpha-2 country and, when the database carries it, the ISO 3166-2
    /// subdivision (e.g. `US-CA`). A single database lookup feeds both
    /// fields. Returns `None` when the address is absent from the
    /// database or carries neither a country nor a subdivision.
    pub fn locate(&self, ip: IpAddr) -> Option<GeoLocation> {
        let reader = self.reader.read().ok()?;
        let record: geoip2::City = reader.lookup(ip).ok()?.decode().ok().flatten()?;
        let country = record.country.iso_code.map(|code| code.to_owned());
        let subdivision = match (
            country.as_deref(),
            record.subdivisions.first().and_then(|sub| sub.iso_code),
        ) {
            (Some(country_code), Some(sub_code)) => Some(format!("{country_code}-{sub_code}")),
            _ => None,
        };
        if country.is_none() && subdivision.is_none() {
            return None;
        }
        Some(GeoLocation {
            country,
            subdivision,
        })
    }

    pub async fn refresh(&self, http: &Client) -> RefreshOutcome {
        let (year, month) = current_year_month();
        let mut last_http_error: Option<String> = None;
        let mut last_parse_error: Option<String> = None;

        for (y, m) in [(year, month), previous_year_month(year, month)] {
            let url = DBIP_URL_TEMPLATE.replace("{ym}", &format!("{y}-{m:02}"));
            match fetch_gzipped(http, &url).await {
                Ok(bytes) => match Reader::from_source(bytes) {
                    Ok(reader) => {
                        if let Ok(mut guard) = self.reader.write() {
                            *guard = reader;
                        }
                        return RefreshOutcome::Updated;
                    }
                    Err(error) => {
                        last_parse_error = Some(format!("{url}: {error}"));
                    }
                },
                Err(error) => {
                    last_http_error = Some(format!("{url}: {error}"));
                }
            }
        }

        if let Some(error) = last_parse_error {
            tracing::warn!(error, "GeoIP refresh parse failed");
            RefreshOutcome::ParseError
        } else {
            tracing::warn!(
                error = last_http_error.unwrap_or_else(|| "unknown".into()),
                "GeoIP refresh download failed"
            );
            RefreshOutcome::HttpError
        }
    }
}

async fn fetch_gzipped(http: &Client, url: &str) -> Result<Vec<u8>, String> {
    let response = http
        .get(url)
        .timeout(REFRESH_DOWNLOAD_TIMEOUT)
        .send()
        .await
        .map_err(|error| format!("send: {error}"))?
        .error_for_status()
        .map_err(|error| format!("status: {error}"))?;
    let mut compressed = Vec::new();
    let mut stream = response.bytes_stream();
    while let Some(chunk) = stream.next().await {
        let chunk = chunk.map_err(|error| format!("body: {error}"))?;
        if compressed.len() + chunk.len() > MAX_COMPRESSED_BYTES {
            return Err(format!(
                "compressed body exceeds {MAX_COMPRESSED_BYTES} bytes"
            ));
        }
        compressed.extend_from_slice(&chunk);
    }
    let decoder = GzDecoder::new(&compressed[..]);
    let mut decompressed = Vec::new();
    decoder
        .take(MAX_DECOMPRESSED_BYTES)
        .read_to_end(&mut decompressed)
        .map_err(|error| format!("gunzip: {error}"))?;
    if decompressed.len() as u64 >= MAX_DECOMPRESSED_BYTES {
        return Err(format!(
            "decompressed payload reached {MAX_DECOMPRESSED_BYTES} byte ceiling"
        ));
    }
    Ok(decompressed)
}

fn current_year_month() -> (i32, u8) {
    let now = OffsetDateTime::now_utc();
    (now.year(), month_index(now.month()))
}

fn previous_year_month(year: i32, month: u8) -> (i32, u8) {
    if month == 1 {
        (year - 1, 12)
    } else {
        (year, month - 1)
    }
}

fn month_index(month: Month) -> u8 {
    match month {
        Month::January => 1,
        Month::February => 2,
        Month::March => 3,
        Month::April => 4,
        Month::May => 5,
        Month::June => 6,
        Month::July => 7,
        Month::August => 8,
        Month::September => 9,
        Month::October => 10,
        Month::November => 11,
        Month::December => 12,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn open_at_returns_none_when_database_missing() {
        let geoip = GeoIp::open_at(Path::new("/tmp/does-not-exist-kura-geoip.mmdb"));
        assert!(geoip.is_none());
    }

    #[test]
    fn previous_year_month_wraps_across_year() {
        assert_eq!(previous_year_month(2026, 1), (2025, 12));
        assert_eq!(previous_year_month(2026, 5), (2026, 4));
    }
}
