//! Append-only cache progress for pipes and agents using a terminal.
use crate::session;
use crate::util::{format_clock, format_duration};
use eyre::Result;
use std::collections::BTreeMap;
use std::ffi::OsStr;
use std::process::ExitCode;
use std::sync::mpsc;
use std::time::{Duration, Instant};
use tuist_cargo_cache_core::AgentStats;

pub(super) fn eligible(arguments: &[String], progress: Option<&str>) -> bool {
    progress != Some("never")
        && matches!(
            super::launch::cargo_subcommand(arguments),
            Some("build" | "b" | "check" | "c" | "clippy" | "run" | "r" | "test" | "t")
        )
        && !arguments
            .iter()
            .take_while(|arg| arg.as_str() != "--")
            .any(|arg| {
                matches!(
                    arg.as_str(),
                    "--quiet" | "--verbose" | "--help" | "--version" | "--message-format"
                ) || arg.starts_with("--message-format=")
                    || (arg.starts_with('-') && !arg.starts_with("--") && short_opt_out(&arg[1..]))
            })
}

fn short_opt_out(flags: &str) -> bool {
    for flag in flags.chars() {
        match flag {
            'q' | 'v' | 'h' | 'V' => return true,
            // Everything after a value-taking flag is its attached value.
            'j' | 'p' | 'F' | 'Z' | 'C' => return false,
            _ => {}
        }
    }
    false
}

pub(super) fn run(
    cargo: &OsStr,
    arguments: &[String],
    environment: BTreeMap<String, String>,
    stats: impl Fn() -> AgentStats + Sync,
) -> Result<ExitCode> {
    with_progress(
        cadence,
        stats,
        |line| crate::logging::note(&line),
        || super::cargo::run_cargo(cargo, arguments, environment),
    )
}

/// How long to wait for the next progress line, given the time already spent.
///
/// The opening minutes are when somebody is still deciding whether to wait for
/// this build, so the line comes often. After that it has less and less to add
/// by saying the same thing again, and the gap widens: a three-hour build
/// reports 34 times rather than the 720 a fixed cadence would produce. That
/// keeps the tail of a long log readable, and keeps a build that is watched by
/// an agent or piped into a file from burying its own result.
fn cadence(elapsed: Duration) -> Duration {
    const LADDER: [(Duration, Duration); 3] = [
        (Duration::from_secs(2 * 60), Duration::from_secs(15)),
        (Duration::from_secs(10 * 60), Duration::from_secs(60)),
        (Duration::from_secs(60 * 60), Duration::from_secs(5 * 60)),
    ];
    LADDER
        .into_iter()
        .find(|(until, _)| elapsed < *until)
        .map_or(Duration::from_secs(15 * 60), |(_, gap)| gap)
}

fn with_progress<T>(
    cadence: impl Fn(Duration) -> Duration + Send,
    stats: impl Fn() -> AgentStats + Sync,
    report: impl Fn(String) + Sync,
    operation: impl FnOnce() -> T,
) -> T {
    std::thread::scope(|scope| {
        let (stop, stopped) = mpsc::channel::<()>();
        let stats = &stats;
        let report = &report;
        scope.spawn(move || {
            let started = Instant::now();
            // The gap is measured from what the build has already spent, so a
            // report that arrives after a widening never lands on the old beat.
            while matches!(
                stopped.recv_timeout(cadence(started.elapsed())),
                Err(mpsc::RecvTimeoutError::Timeout)
            ) {
                report(line(started.elapsed(), &stats()));
            }
        });
        // Cargo retains its inherited streams, signals, arguments and runners.
        // Dropping the sender also interrupts the wait when operation unwinds.
        let result = operation();
        drop(stop);
        result
    })
}

/// Elapsed time here is a clock reading rather than a measurement: the line
/// repeats for as long as the build runs, so by the time anyone cares about it,
/// it is reporting a quarter of an hour. That reads "13m 33s", not "813s".
fn line(elapsed: Duration, stats: &AgentStats) -> String {
    format!(
        "tuist_cargo_cache[progress]: {} elapsed; {} hits, {} misses, {} bypassed, {} not looked up; ~{} compiler work saved",
        format_clock(elapsed),
        stats.hits,
        session::cache_misses(stats),
        session::unexpected_bypasses(stats),
        stats.unconsulted,
        format_duration(Duration::from_nanos(stats.avoided_compiler_duration_ns)),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn long_commands_report_without_changing_the_result_or_using_terminal_controls() {
        let (send, receive) = mpsc::channel();
        let result = with_progress(
            |_| Duration::from_millis(5),
            || {
                let mut stats = AgentStats::default();
                stats.hits = 1;
                stats.lookups = 3;
                stats.compiler = std::collections::BTreeMap::from([(
                    "miss".into(),
                    tuist_cargo_cache_core::CompilerStats::new(2, 0),
                )]);
                stats.avoided_compiler_duration_ns = 1_500_000_000;
                stats
            },
            |line| send.send(line).unwrap(),
            || {
                let line = receive.recv_timeout(Duration::from_secs(2)).unwrap();
                assert!(line.contains("1 hits, 2 misses"));
                assert!(line.contains("~1.50s compiler work saved"));
                assert!(!line.contains(['\r', '\x1b']));
                101
            },
        );
        assert_eq!(result, 101);
    }

    #[test]
    fn a_long_build_reports_its_time_as_a_clock_reading() {
        let mut stats = AgentStats::default();
        stats.avoided_compiler_duration_ns = 1_840_000_000_000;
        let reported = line(Duration::from_secs(813), &stats);
        assert!(reported.contains("13m 33s elapsed"), "{reported}");
        assert!(
            reported.contains("~30m 40s compiler work saved"),
            "{reported}"
        );
    }

    #[test]
    fn a_long_build_reports_less_and_less_often() {
        // Fifteen seconds while the build is still young enough to abandon.
        assert_eq!(cadence(Duration::ZERO), Duration::from_secs(15));
        assert_eq!(cadence(Duration::from_secs(119)), Duration::from_secs(15));
        // Then a minute, then five, then a quarter of an hour for as long as it
        // takes. Each step is a round number so the log reads as a cadence.
        assert_eq!(cadence(Duration::from_secs(120)), Duration::from_secs(60));
        assert_eq!(cadence(Duration::from_secs(599)), Duration::from_secs(60));
        assert_eq!(cadence(Duration::from_secs(600)), Duration::from_secs(300));
        assert_eq!(
            cadence(Duration::from_secs(3_599)),
            Duration::from_secs(300)
        );
        assert_eq!(
            cadence(Duration::from_secs(3_600)),
            Duration::from_secs(900)
        );
        assert_eq!(
            cadence(Duration::from_secs(12 * 3_600)),
            Duration::from_secs(900)
        );

        let mut elapsed = Duration::ZERO;
        let mut reports = 0;
        while elapsed < Duration::from_secs(3 * 3_600) {
            elapsed += cadence(elapsed);
            reports += 1;
        }
        // A fixed fifteen seconds would have said it 720 times.
        assert_eq!(reports, 34, "reports during a three-hour build");
    }

    #[test]
    fn short_commands_stop_reporting_immediately() {
        let started = Instant::now();
        with_progress(
            |_| Duration::from_secs(60),
            AgentStats::default,
            |_| panic!("short command reported"),
            || (),
        );
        assert!(started.elapsed() < Duration::from_secs(2));
    }
}

#[cfg(test)]
mod policy_tests {
    use super::*;
    #[test]
    fn plain_progress_honors_opt_out_and_allows_cargo_presentation_flags() {
        let args = ["build", "--color=always", "--config", "build.jobs=2"].map(str::to_string);
        assert!(eligible(&args, None));
        assert!(!eligible(&args, Some("never")));
        assert!(!eligible(
            &["build".into(), "--message-format=json".into()],
            None
        ));
        assert!(!eligible(&["build".into(), "-q".into()], None));
        assert!(eligible(
            &["run".into(), "--".into(), "--quiet".into()],
            None
        ));
    }
}

#[cfg(test)]
mod argument_tests {
    use super::*;
    #[test]
    fn global_options_and_attached_values_keep_progress() {
        for arguments in [
            vec!["--color", "always", "build"],
            vec!["+nightly", "--config", "build.jobs=2", "check"],
            vec!["--config=build.jobs=2", "build", "-Zunstable-options"],
            vec!["build", "-Fchrono", "-pwhatever"],
        ] {
            assert!(eligible(
                &arguments.iter().map(|s| s.to_string()).collect::<Vec<_>>(),
                None
            ));
        }
        for flag in ["-q", "-vv", "-vq", "-vFchrono", "--verbose"] {
            assert!(!eligible(&["build".into(), flag.into()], None));
        }
    }
}
