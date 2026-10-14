use prost::Message;
use std::time::Duration;
use tonic::{Code, Status};

#[derive(Clone, PartialEq, Message)]
struct RpcStatus {
    #[prost(int32, tag = "1")]
    code: i32,
    #[prost(string, tag = "2")]
    message: String,
    #[prost(message, repeated, tag = "3")]
    details: Vec<Detail>,
}
#[derive(Clone, PartialEq, Message)]
struct Detail {
    #[prost(string, tag = "1")]
    type_url: String,
    #[prost(bytes = "vec", tag = "2")]
    value: Vec<u8>,
}
#[derive(Clone, PartialEq, Message)]
struct RetryInfo {
    #[prost(message, optional, tag = "1")]
    delay: Option<RetryDelay>,
}
#[derive(Clone, PartialEq, Message)]
struct RetryDelay {
    #[prost(int64, tag = "1")]
    seconds: i64,
    #[prost(int32, tag = "2")]
    nanos: i32,
}

pub(crate) fn delay(status: &Status, attempt: i64) -> Option<Duration> {
    if !matches!(
        status.code(),
        Code::Unavailable | Code::DeadlineExceeded | Code::ResourceExhausted
    ) {
        return None;
    }
    if let Ok(rpc) = RpcStatus::decode(status.details()) {
        for detail in rpc.details {
            if !detail.type_url.ends_with("/google.rpc.RetryInfo") {
                continue;
            }
            let hint = RetryInfo::decode(detail.value.as_slice()).ok()?.delay?;
            if hint.seconds < 0 || !(0..1_000_000_000).contains(&hint.nanos) {
                return None;
            }
            let delay = Duration::new(hint.seconds as u64, hint.nanos as u32);
            if delay > Duration::from_secs(10) {
                return None;
            }
            return Some(delay);
        }
    }
    Some(Duration::from_millis(100 * (1u64 << attempt.clamp(0, 3))))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn admission_hints_are_honored_without_retrying_permanent_errors() {
        let details = RpcStatus {
            code: 8,
            message: "busy".into(),
            details: vec![Detail {
                type_url: "type.googleapis.com/google.rpc.RetryInfo".into(),
                value: RetryInfo {
                    delay: Some(RetryDelay {
                        seconds: 2,
                        nanos: 0,
                    }),
                }
                .encode_to_vec(),
            }],
        }
        .encode_to_vec();
        let status = Status::with_details(Code::ResourceExhausted, "busy", details.into());
        assert_eq!(delay(&status, 0), Some(Duration::from_secs(2)));
        assert_eq!(
            delay(&Status::unavailable("retry"), 1),
            Some(Duration::from_millis(200))
        );
        assert_eq!(delay(&Status::permission_denied("no"), 0), None);
        assert_eq!(delay(&Status::invalid_argument("no"), 0), None);
    }
}
