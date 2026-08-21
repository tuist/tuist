//! Resolving a `Range` request header against a stored artifact.
//!
//! Shared by the two serving planes so a resume behaves identically whichever
//! one answers it: the sendfile accelerator on the plain public listener, and
//! the Axum path that serves everything else (TLS, non-Linux, inline bodies).

/// The slice of an artifact one response carries, resolved from the request's
/// `Range` header against the stored size.
///
/// Every artifact response has one: an unranged request resolves to the
/// whole artifact with `partial` false, so the transfer, the `Content-Length`
/// and the response-stream reservation are all driven by the same two numbers
/// whether or not the client asked to resume.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ServedRange {
    pub start: u64,
    pub length: u64,
    pub partial: bool,
}

impl ServedRange {
    pub fn full(size: u64) -> Self {
        Self {
            start: 0,
            length: size,
            partial: false,
        }
    }

    pub fn status(self) -> (u16, &'static str) {
        if self.partial {
            (206, "Partial Content")
        } else {
            (200, "OK")
        }
    }

    /// The `Content-Range` value for a satisfied partial response. `None` for a
    /// full response, which must not carry the header.
    pub fn content_range(self, size: u64) -> Option<String> {
        if !self.partial {
            return None;
        }
        let last = self.start.saturating_add(self.length).saturating_sub(1);
        Some(format!("bytes {}-{last}/{size}", self.start))
    }
}

/// What a request's `Range` header resolved to against the artifact's size.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RangeOutcome {
    /// Serve the whole artifact: no `Range` header, or one this server does not
    /// honour. Ignoring a range we do not implement is allowed, and is what
    /// keeps multi-range requests working instead of failing them.
    Full,
    Partial(ServedRange),
    /// The range is well formed but falls entirely outside the artifact, which
    /// is the one case that must be refused rather than widened to a 200.
    Unsatisfiable,
}

/// Resolves a single byte range against `size`.
///
/// Deliberately narrow: one `bytes=` range per request. Resume, the reason this
/// exists, needs exactly `bytes=<received>-`, and a multipart/byteranges body
/// would have to be assembled by hand on a path whose whole point is handing
/// the file to `sendfile`. Anything outside that shape resolves to `Full` so
/// the client still gets its bytes.
pub fn resolve_range(header: Option<&str>, size: u64) -> RangeOutcome {
    let Some(header) = header else {
        return RangeOutcome::Full;
    };
    let Some(spec) = header.trim().strip_prefix("bytes=") else {
        return RangeOutcome::Full;
    };
    let spec = spec.trim();
    // A multi-range request: served whole rather than refused.
    if spec.contains(',') {
        return RangeOutcome::Full;
    }
    let Some((first, last)) = spec.split_once('-') else {
        return RangeOutcome::Full;
    };
    let (first, last) = (first.trim(), last.trim());

    let (start, end_inclusive) = if first.is_empty() {
        // `bytes=-N`: the final N bytes. A suffix at least as long as the
        // artifact is the whole artifact, not an error.
        let Ok(suffix) = last.parse::<u64>() else {
            return RangeOutcome::Full;
        };
        if suffix == 0 || size == 0 {
            return RangeOutcome::Unsatisfiable;
        }
        (size.saturating_sub(suffix.min(size)), size - 1)
    } else {
        let Ok(start) = first.parse::<u64>() else {
            return RangeOutcome::Full;
        };
        if start >= size {
            return RangeOutcome::Unsatisfiable;
        }
        let end_inclusive = if last.is_empty() {
            size - 1
        } else {
            let Ok(end) = last.parse::<u64>() else {
                return RangeOutcome::Full;
            };
            if end < start {
                return RangeOutcome::Unsatisfiable;
            }
            end.min(size - 1)
        };
        (start, end_inclusive)
    };

    let length = end_inclusive - start + 1;
    // A range covering the whole artifact is still answered as a 206: the
    // client asked with a Range header, and 206 keeps the reply's meaning
    // unambiguous when it retries.
    RangeOutcome::Partial(ServedRange {
        start,
        length,
        partial: true,
    })
}

#[cfg(test)]
mod tests {
    use super::{RangeOutcome, ServedRange, resolve_range};

    fn partial(start: u64, length: u64) -> RangeOutcome {
        RangeOutcome::Partial(ServedRange {
            start,
            length,
            partial: true,
        })
    }

    #[test]
    fn a_request_without_a_range_serves_the_whole_artifact() {
        assert_eq!(resolve_range(None, 100), RangeOutcome::Full);
    }

    #[test]
    fn an_open_ended_range_serves_the_tail() {
        // The shape a resume actually sends: everything from what it already
        // has to the end.
        assert_eq!(resolve_range(Some("bytes=90-"), 100), partial(90, 10));
        assert_eq!(resolve_range(Some("bytes=0-"), 100), partial(0, 100));
    }

    #[test]
    fn a_closed_range_is_inclusive_and_clamps_to_the_artifact() {
        assert_eq!(resolve_range(Some("bytes=0-0"), 100), partial(0, 1));
        assert_eq!(resolve_range(Some("bytes=10-19"), 100), partial(10, 10));
        assert_eq!(resolve_range(Some("bytes=10-999"), 100), partial(10, 90));
    }

    #[test]
    fn a_suffix_range_counts_back_from_the_end() {
        assert_eq!(resolve_range(Some("bytes=-10"), 100), partial(90, 10));
        // A suffix longer than the artifact is the whole artifact, not an error.
        assert_eq!(resolve_range(Some("bytes=-500"), 100), partial(0, 100));
    }

    #[test]
    fn a_range_past_the_end_is_refused_rather_than_widened() {
        // Refusing matters: silently answering 200 would make a client that
        // appends to a partial file corrupt it.
        assert_eq!(
            resolve_range(Some("bytes=100-"), 100),
            RangeOutcome::Unsatisfiable
        );
        assert_eq!(
            resolve_range(Some("bytes=200-300"), 100),
            RangeOutcome::Unsatisfiable
        );
        assert_eq!(
            resolve_range(Some("bytes=-0"), 100),
            RangeOutcome::Unsatisfiable
        );
        assert_eq!(
            resolve_range(Some("bytes=5-1"), 100),
            RangeOutcome::Unsatisfiable
        );
        assert_eq!(
            resolve_range(Some("bytes=0-"), 0),
            RangeOutcome::Unsatisfiable
        );
    }

    #[test]
    fn ranges_this_server_does_not_honour_fall_back_to_the_whole_artifact() {
        for header in [
            "bytes=0-9,20-29",
            "items=0-9",
            "bytes=abc-",
            "bytes=0-abc",
            "bytes=",
            "0-9",
        ] {
            assert_eq!(
                resolve_range(Some(header), 100),
                RangeOutcome::Full,
                "{header}"
            );
        }
    }

    #[test]
    fn only_a_partial_response_carries_a_content_range() {
        assert_eq!(ServedRange::full(100).content_range(100), None);
        assert_eq!(ServedRange::full(100).status(), (200, "OK"));

        let RangeOutcome::Partial(range) = resolve_range(Some("bytes=90-"), 100) else {
            panic!("expected a partial range");
        };
        assert_eq!(range.status(), (206, "Partial Content"));
        assert_eq!(range.content_range(100).as_deref(), Some("bytes 90-99/100"));
    }

    #[test]
    fn a_single_byte_range_reports_one_byte_not_zero() {
        let RangeOutcome::Partial(range) = resolve_range(Some("bytes=99-99"), 100) else {
            panic!("expected a partial range");
        };
        assert_eq!(range.length, 1);
        assert_eq!(range.content_range(100).as_deref(), Some("bytes 99-99/100"));
    }
}
