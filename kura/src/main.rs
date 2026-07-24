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
// tikv-jemallocator uses a prefixed jemalloc build by default and documents
// this exact symbol for setting its boot-time configuration.
#[cfg(target_os = "linux")]
#[used]
#[unsafe(export_name = "_rjem_malloc_conf")]
static JEMALLOC_MALLOC_CONF: Option<&'static std::ffi::c_char> = Some(unsafe {
    JemallocConfigPointer {
        bytes: &b"background_thread:true,max_background_threads:1,dirty_decay_ms:4000,muzzy_decay_ms:4000\0"[0],
    }
    .c_char
});

fn main() {
    #[cfg(target_os = "linux")]
    if let Err(error) = verify_jemalloc_configuration() {
        eprintln!("invalid jemalloc configuration: {error}");
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
            eprintln!("failed to build tokio runtime: {error}");
            std::process::exit(1);
        }
    };

    runtime.block_on(async {
        if let Err(error) = kura::run().await {
            eprintln!("{error}");
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

    Ok(())
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
