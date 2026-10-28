#[cfg(not(target_env = "msvc"))]
#[global_allocator]
static GLOBAL: tikv_jemallocator::Jemalloc = tikv_jemallocator::Jemalloc;

#[cfg(target_os = "linux")]
union JemallocConfigPointer {
    bytes: &'static u8,
    c_char: &'static std::ffi::c_char,
}

// Keep allocator page reclamation independent of subsequent allocation
// traffic so a burst can return memory while the service is otherwise idle.
// jemalloc reads its boot-time configuration from this documented symbol. On
// linux-gnu the build is unprefixed (see Cargo.toml), so the symbol is the
// plain `malloc_conf`; everywhere else tikv-jemalloc-sys keeps the `_rjem_`
// prefix.
#[cfg(target_os = "linux")]
#[used]
#[cfg_attr(target_env = "gnu", unsafe(export_name = "malloc_conf"))]
#[cfg_attr(not(target_env = "gnu"), unsafe(export_name = "_rjem_malloc_conf"))]
static JEMALLOC_MALLOC_CONF: Option<&'static std::ffi::c_char> = Some(unsafe {
    JemallocConfigPointer {
        bytes: &b"background_thread:true,max_background_threads:1,dirty_decay_ms:4000,muzzy_decay_ms:4000\0"[0],
    }
    .c_char
});

fn main() {
    if matches!(std::env::args().nth(1).as_deref(), Some("--version" | "-V")) {
        println!("kura {}", kura::VERSION);
        return;
    }

    #[cfg(target_os = "linux")]
    if let Err(error) = verify_jemalloc_configuration() {
        report_fatal(
            "kura.allocator.configuration_invalid",
            "invalid allocator configuration",
            &error,
        );
        std::process::exit(1);
    }

    let worker_threads = resolve_worker_threads();
    let runtime = match tokio::runtime::Builder::new_multi_thread()
        .worker_threads(worker_threads)
        .enable_all()
        .build()
    {
        Ok(runtime) => runtime,
        Err(error) => {
            report_fatal(
                "kura.runtime.initialization_failed",
                "failed to initialize asynchronous runtime",
                &error,
            );
            std::process::exit(1);
        }
    };

    runtime.block_on(async {
        if let Err(error) = kura::run().await {
            report_fatal("kura.runtime.failed", "Kura stopped with an error", &error);
            std::process::exit(1);
        }
    });
}

#[cfg(target_os = "linux")]
fn verify_jemalloc_configuration() -> Result<(), String> {
    use tikv_jemalloc_ctl::{background_thread, max_background_threads, opt, raw};

    let configured_background_thread = opt::background_thread::read()
        .map_err(|error| format!("failed to read opt.background_thread: {error}"))?;
    let running_background_thread = background_thread::read()
        .map_err(|error| format!("failed to read background_thread: {error}"))?;
    let configured_max_background_threads =
        unsafe { raw::read::<usize>(b"opt.max_background_threads\0") }
            .map_err(|error| format!("failed to read opt.max_background_threads: {error}"))?;
    let running_max_background_threads = max_background_threads::read()
        .map_err(|error| format!("failed to read max_background_threads: {error}"))?;
    let dirty_decay_ms = unsafe { raw::read::<isize>(b"opt.dirty_decay_ms\0") }
        .map_err(|error| format!("failed to read opt.dirty_decay_ms: {error}"))?;
    let muzzy_decay_ms = unsafe { raw::read::<isize>(b"opt.muzzy_decay_ms\0") }
        .map_err(|error| format!("failed to read opt.muzzy_decay_ms: {error}"))?;

    if !configured_background_thread || !running_background_thread {
        return Err("background page-reclamation thread is not running".into());
    }
    if configured_max_background_threads != 1 || running_max_background_threads != 1 {
        return Err(format!(
            "expected one background page-reclamation thread, configured={configured_max_background_threads} running={running_max_background_threads}"
        ));
    }
    if dirty_decay_ms != 4_000 || muzzy_decay_ms != 4_000 {
        return Err(format!(
            "expected 4000ms decay, dirty={dirty_decay_ms}ms muzzy={muzzy_decay_ms}ms"
        ));
    }

    // The `malloc` that shared libraries (libstdc++ for rocksdb's C++) resolve
    // at load time must be jemalloc's, otherwise their allocations land in
    // glibc arenas that neither the decay tuning above nor the memory-pressure
    // trims can reclaim. RTLD_DEFAULT follows the same lookup order as their
    // PLT resolution, so it sees the interposition (or its absence) as they do.
    #[cfg(target_env = "gnu")]
    {
        let resolved = unsafe { libc::dlsym(libc::RTLD_DEFAULT, c"malloc".as_ptr()) };
        if resolved as *const () != tikv_jemalloc_sys::malloc as *const () {
            return Err("libc malloc is not interposed by jemalloc".into());
        }
    }

    Ok(())
}

fn report_fatal(event_name: &str, message: &str, error: &dyn std::fmt::Display) {
    eprintln!(
        "{}",
        serde_json::json!({
            "level": "ERROR",
            "event.name": event_name,
            "message": message,
            "error": error.to_string(),
            "service.name": "kura",
            "service.version": kura::VERSION,
        })
    );
}

fn resolve_worker_threads() -> usize {
    if let Ok(value) = std::env::var("KURA_TOKIO_WORKER_THREADS")
        && let Ok(parsed) = value.parse::<usize>()
        && parsed > 0
    {
        return parsed;
    }
    std::thread::available_parallelism()
        .map(|count| count.get())
        .unwrap_or(2)
        .clamp(2, 16)
}

#[cfg(test)]
mod tests {
    #[cfg(target_os = "linux")]
    #[test]
    fn jemalloc_boot_configuration_is_active() {
        super::verify_jemalloc_configuration().expect("jemalloc configuration should be active");
    }
}
