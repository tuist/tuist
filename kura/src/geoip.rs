use std::{io::Read, net::IpAddr, path::Path, sync::RwLock, time::Duration};

use flate2::read::GzDecoder;
use maxminddb::{Reader, geoip2};
use reqwest::Client;
use time::{Month, OffsetDateTime};

/// Path of the DB-IP Lite Country MMDB vendored into the Kura container
/// image. The Dockerfile downloads the monthly dump at build time and
/// drops it here, so the database is always available at startup in
/// official deployments. Self-built images that omit this file degrade
/// gracefully — [`GeoIp::open`] returns `None` and country attribution
/// is silently skipped.
pub const GEOIP_DATABASE_PATH: &str = "/opt/geoip/dbip-country-lite.mmdb";

const DBIP_URL_TEMPLATE: &str = "https://download.db-ip.com/free/dbip-country-lite-{ym}.mmdb.gz";
const REFRESH_DOWNLOAD_TIMEOUT: Duration = Duration::from_secs(60);
/// Hard ceiling on the compressed body the refresher will accept from
/// DB-IP. Recent DB-IP Lite Country dumps are ~7 MiB compressed; 16 MiB
/// gives ample headroom while keeping refresh memory predictably bounded.
const MAX_COMPRESSED_BYTES: usize = 16 * 1024 * 1024;
/// Hard ceiling on the decompressed payload the refresher will accept.
/// Country-level MMDB dumps land around ~10 MiB decompressed today;
/// 32 MiB leaves room for organic growth without unbounded allocation.
const MAX_DECOMPRESSED_BYTES: u64 = 32 * 1024 * 1024;

pub struct GeoIp {
    reader: RwLock<Reader<Vec<u8>>>,
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
                    "GeoIP database not loaded; client country attribution disabled"
                );
                None
            }
        }
    }

    pub fn country_code(&self, ip: IpAddr) -> Option<String> {
        let reader = self.reader.read().ok()?;
        let record: geoip2::Country = reader.lookup(ip).ok()?.decode().ok().flatten()?;
        record.country.iso_code.map(|code| code.to_owned())
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
    let compressed = response
        .bytes()
        .await
        .map_err(|error| format!("body: {error}"))?;
    if compressed.len() > MAX_COMPRESSED_BYTES {
        return Err(format!(
            "compressed body exceeds {MAX_COMPRESSED_BYTES} bytes"
        ));
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
