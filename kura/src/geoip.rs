use std::{
    io::Read,
    net::IpAddr,
    sync::{Arc, Mutex},
    time::Duration,
};

use flate2::read::GzDecoder;
use maxminddb::{Reader, geoip2};
use reqwest::Client;
use time::{Month, OffsetDateTime};

use crate::config::GeoIpConfig;

const DBIP_URL_TEMPLATE: &str = "https://download.db-ip.com/free/dbip-country-lite-{ym}.mmdb.gz";
const REFRESH_DOWNLOAD_TIMEOUT: Duration = Duration::from_secs(60);
const REFRESH_MAX_BYTES: usize = 64 * 1024 * 1024;

#[derive(Clone)]
pub struct GeoIp {
    reader: Arc<Mutex<Arc<Reader<Vec<u8>>>>>,
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
    pub fn from_config(config: Option<&GeoIpConfig>) -> Result<Option<Self>, String> {
        let Some(config) = config else {
            return Ok(None);
        };
        let reader = Reader::open_readfile(&config.database_path).map_err(|error| {
            format!(
                "failed to open GeoIP database at {}: {error}",
                config.database_path.display()
            )
        })?;
        Ok(Some(Self {
            reader: Arc::new(Mutex::new(Arc::new(reader))),
        }))
    }

    pub fn country_code(&self, ip: IpAddr) -> Option<String> {
        let reader = self.snapshot()?;
        let country: Option<geoip2::Country> = reader.lookup(ip).ok().flatten();
        country
            .and_then(|record| record.country)
            .and_then(|c| c.iso_code)
            .map(|code| code.to_owned())
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
                        self.install(Arc::new(reader));
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

    fn snapshot(&self) -> Option<Arc<Reader<Vec<u8>>>> {
        let guard = self.reader.lock().ok()?;
        Some(Arc::clone(&*guard))
    }

    fn install(&self, reader: Arc<Reader<Vec<u8>>>) {
        if let Ok(mut guard) = self.reader.lock() {
            *guard = reader;
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
    if compressed.len() > REFRESH_MAX_BYTES {
        return Err(format!("compressed body exceeds {REFRESH_MAX_BYTES} bytes"));
    }
    let decoder = GzDecoder::new(&compressed[..]);
    let mut decompressed = Vec::with_capacity(compressed.len() * 4);
    decoder
        .take(REFRESH_MAX_BYTES as u64)
        .read_to_end(&mut decompressed)
        .map_err(|error| format!("gunzip: {error}"))?;
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
    fn from_config_returns_none_when_disabled() {
        let geoip = GeoIp::from_config(None).expect("from_config should succeed");
        assert!(geoip.is_none());
    }

    #[test]
    fn from_config_returns_error_for_missing_database() {
        let config = GeoIpConfig {
            database_path: "/tmp/does-not-exist-kura-geoip.mmdb".into(),
            refresh_interval_secs: 0,
        };
        let result = GeoIp::from_config(Some(&config));
        assert!(result.is_err());
    }

    #[test]
    fn previous_year_month_wraps_across_year() {
        assert_eq!(previous_year_month(2026, 1), (2025, 12));
        assert_eq!(previous_year_month(2026, 5), (2026, 4));
    }
}
