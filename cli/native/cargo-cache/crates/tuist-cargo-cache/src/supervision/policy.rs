//! Pure suspension decisions; kernel operations and clocks are injected by the caller.
#[derive(Default)]
pub(super) struct Policy {
    pressure_since: Option<u64>,
    last_change: Option<u64>,
}
#[derive(Debug, PartialEq, Eq)]
pub(super) enum Change {
    Freeze(usize),
    Resume(usize),
}
impl Policy {
    /// Actions are ordered oldest first. A frozen successor to a completed
    /// oldest action is resumed immediately, even while pressure persists.
    pub(super) fn step(&mut self, now: u64, pressured: bool, frozen: &[bool]) -> Option<Change> {
        if self.last_change.is_some_and(|last| now < last)
            || self.pressure_since.is_some_and(|start| now < start)
        {
            *self = Self::default();
        }
        if pressured {
            self.pressure_since.get_or_insert(now);
        } else {
            self.pressure_since = None;
        }
        let change = if frozen.first() == Some(&true) {
            Some(Change::Resume(0))
        } else if self
            .last_change
            .is_some_and(|last| now.saturating_sub(last) < 1_000)
        {
            None
        } else if !pressured {
            frozen.iter().position(|frozen| *frozen).map(Change::Resume)
        } else if self
            .pressure_since
            .is_some_and(|start| now.saturating_sub(start) >= 2_000)
        {
            frozen
                .iter()
                .enumerate()
                .skip(1)
                .rev()
                .find(|(_, frozen)| !**frozen)
                .map(|(i, _)| Change::Freeze(i))
        } else {
            None
        };
        if change.is_some() {
            self.last_change = Some(now);
        }
        change
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn a_clock_reversal_cannot_strand_suspended_work() {
        let mut policy = Policy::default();
        assert_eq!(
            policy.step(5_000, false, &[false, true, true]),
            Some(Change::Resume(1))
        );
        assert_eq!(
            policy.step(1_000, false, &[false, false, true]),
            Some(Change::Resume(2))
        );
    }

    #[test]
    fn newest_first_and_oldest_keeps_running() {
        let mut policy = Policy::default();
        assert_eq!(policy.step(0, true, &[false, false, false]), None);
        assert_eq!(policy.step(1_999, true, &[false, false, false]), None);
        assert_eq!(
            policy.step(2_000, true, &[false, false, false]),
            Some(Change::Freeze(2))
        );
        assert_eq!(policy.step(2_999, true, &[false, false, true]), None);
        assert_eq!(
            policy.step(3_000, true, &[false, false, true]),
            Some(Change::Freeze(1))
        );
        assert_eq!(policy.step(4_000, true, &[false, true, true]), None);
        // The oldest finished: immediately resume its successor for progress.
        assert_eq!(
            policy.step(4_001, true, &[true, true]),
            Some(Change::Resume(0))
        );
    }
    #[test]
    fn recovery_resumes_oldest_before_new_work() {
        let mut policy = Policy::default();
        assert_eq!(
            policy.step(0, false, &[false, true, true]),
            Some(Change::Resume(1))
        );
        assert_eq!(policy.step(500, false, &[false, false, true]), None);
        assert_eq!(
            policy.step(1_000, false, &[false, false, true]),
            Some(Change::Resume(2))
        );
        assert_eq!(policy.step(2_000, true, &[false]), None);
        assert_eq!(policy.step(5_000, true, &[false]), None);
    }
}
