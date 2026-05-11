#[cfg(not(target_env = "msvc"))]
#[global_allocator]
static GLOBAL: tikv_jemallocator::Jemalloc = tikv_jemallocator::Jemalloc;

fn main() {
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
