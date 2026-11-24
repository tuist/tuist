const RECOVERY_NUMERATOR: u64 = 9;
const RECOVERY_DENOMINATOR: u64 = 10;

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum MemoryPressure {
    Normal,
    Constrained,
    Critical,
}

impl MemoryPressure {
    pub(super) fn as_u8(self) -> u8 {
        match self {
            Self::Normal => 0,
            Self::Constrained => 1,
            Self::Critical => 2,
        }
    }

    pub fn as_i64(self) -> i64 {
        self.as_u8() as i64
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Normal => "normal",
            Self::Constrained => "constrained",
            Self::Critical => "critical",
        }
    }

    pub(super) fn from_u8(value: u8) -> Self {
        match value {
            1 => Self::Constrained,
            2 => Self::Critical,
            _ => Self::Normal,
        }
    }
}

pub(super) fn recovery_bytes(limit: u64) -> u64 {
    limit
        .saturating_mul(RECOVERY_NUMERATOR)
        .saturating_div(RECOVERY_DENOMINATOR)
}

pub(super) fn transition(
    current: MemoryPressure,
    resident_bytes: u64,
    soft_limit_bytes: u64,
    hard_limit_bytes: u64,
) -> MemoryPressure {
    match current {
        MemoryPressure::Normal => {
            if resident_bytes >= hard_limit_bytes {
                MemoryPressure::Critical
            } else if resident_bytes >= soft_limit_bytes {
                MemoryPressure::Constrained
            } else {
                MemoryPressure::Normal
            }
        }
        MemoryPressure::Constrained => {
            if resident_bytes >= hard_limit_bytes {
                MemoryPressure::Critical
            } else if resident_bytes <= recovery_bytes(soft_limit_bytes) {
                MemoryPressure::Normal
            } else {
                MemoryPressure::Constrained
            }
        }
        MemoryPressure::Critical => {
            if resident_bytes <= recovery_bytes(soft_limit_bytes) {
                MemoryPressure::Normal
            } else if resident_bytes <= recovery_bytes(hard_limit_bytes) {
                MemoryPressure::Constrained
            } else {
                MemoryPressure::Critical
            }
        }
    }
}
