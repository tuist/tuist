#[tokio::main]
async fn main() {
    if let Err(error) = kura::run().await {
        eprintln!("{error}");
        std::process::exit(1);
    }
}
