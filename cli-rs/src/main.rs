mod spec;
mod swift;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // `tuist --mcp` is a long-lived tool server; every command it runs gets its own process.
    if std::env::args().nth(1).as_deref() == Some("--mcp") {
        swift::run_commands_in_children();
    }
    spec::build_cli().serve().await
}
