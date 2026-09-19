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

/// The entity tag for a stored representation.
///
/// `version_ms` is the discriminator: the store refuses a write whose version
/// does not advance past the one already held, so every accepted replacement
/// under a key has a strictly greater value. Size rides along because it is
/// free and rules out a same-millisecond pair whose lengths differ.
pub fn entity_tag(version_ms: u64, size: u64) -> String {
    format!("\"{version_ms}-{size}\"")
}

/// The range-related headers of one request.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct RangeRequest<'a> {
    pub range: Option<&'a str>,
    pub if_range: Option<&'a str>,
}

impl<'a> RangeRequest<'a> {
    pub fn new(range: Option<&'a str>, if_range: Option<&'a str>) -> Self {
        Self { range, if_range }
    }
}

/// Resolves a range against `size`, honouring `If-Range`.
///
/// Range resume is only safe while the bytes already in the client's hand and
/// the bytes about to be sent belong to the same representation. A key here can
/// be rewritten at any time, and the replacement is served from offset zero
/// like any other artifact, so an offset check alone cannot tell a resumed tail
/// apart from a different artifact's tail: both start exactly where the client
/// asked. Two versions of the same size make the sizes agree as well.
///
/// So a resume that names a validator it no longer matches is answered with the
/// whole artifact instead of the tail. That costs the client the bytes it had
/// and is the point: a 200 tells it to start over, where a 206 would have it
/// splice one artifact's head onto another's tail and store the result under a
/// key that describes neither.
pub fn resolve_conditional_range(request: RangeRequest<'_>, etag: &str, size: u64) -> RangeOutcome {
    if let Some(if_range) = request.if_range
        && if_range.trim() != etag
    {
        return RangeOutcome::Full;
    }
    resolve_range(request.range, size)
}

#[cfg(test)]
mod tests {
    use super::{
        RangeOutcome, RangeRequest, ServedRange, entity_tag, resolve_conditional_range,
        resolve_range,
    };

    #[test]
    fn a_resume_naming_the_representation_it_started_from_is_served_its_tail() {
        let etag = entity_tag(10, 100);
        assert_eq!(
            resolve_conditional_range(
                RangeRequest::new(Some("bytes=40-"), Some(&etag)),
                &etag,
                100
            ),
            partial(40, 60)
        );
    }

    #[test]
    fn a_resume_is_served_the_whole_artifact_once_a_replacement_of_the_same_size_lands() {
        // The offset alone cannot separate these two: a replacement is served
        // from zero like any artifact, so its tail begins exactly where the
        // client asked, and an equal size leaves the lengths agreeing too. The
        // validator is the only thing that differs, so it has to be what
        // decides.
        let started_from = entity_tag(10, 100);
        let now_stored = entity_tag(11, 100);
        assert_ne!(started_from, now_stored);
        assert_eq!(
            resolve_conditional_range(
                RangeRequest::new(Some("bytes=40-"), Some(&started_from)),
                &now_stored,
                100
            ),
            RangeOutcome::Full
        );
    }

    #[test]
    fn a_range_without_a_validator_is_resolved_on_the_offset_alone() {
        let etag = entity_tag(10, 100);
        assert_eq!(
            resolve_conditional_range(RangeRequest::new(Some("bytes=40-"), None), &etag, 100),
            partial(40, 60)
        );
    }

    #[test]
    fn a_stale_validator_outranks_a_range_that_falls_outside_the_artifact() {
        // Answering 416 here would tell the client its range is impossible,
        // when what actually happened is that the artifact it was reading was
        // replaced. It gets the whole of the current one instead.
        assert_eq!(
            resolve_conditional_range(
                RangeRequest::new(Some("bytes=400-"), Some(&entity_tag(10, 100))),
                &entity_tag(11, 100),
                100
            ),
            RangeOutcome::Full
        );
    }

    #[test]
    fn a_validator_is_matched_ignoring_the_whitespace_a_client_may_pad_it_with() {
        let etag = entity_tag(10, 100);
        assert_eq!(
            resolve_conditional_range(
                RangeRequest::new(Some("bytes=40-"), Some(&format!(" {etag} "))),
                &etag,
                100
            ),
            partial(40, 60)
        );
    }

    #[test]
    fn a_version_bump_alone_changes_the_validator() {
        assert_ne!(entity_tag(10, 100), entity_tag(11, 100));
        assert_eq!(entity_tag(10, 100), entity_tag(10, 100));
    }

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
