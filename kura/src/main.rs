#[cfg(not(target_env = "msvc"))]
#[global_allocator]
static GLOBAL: tikv_jemallocator::Jemalloc = tikv_jemallocator::Jemalloc;

fn main() {
    if matches!(std::env::args().nth(1).as_deref(), Some("--version" | "-V")) {
        println!("kura {}", kura::VERSION);
        return;
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
