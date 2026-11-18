use std::fs::{File, OpenOptions, TryLockError};
use std::io::{Read, Write};
use std::net::{Shutdown, TcpListener, TcpStream};
use std::path::Path;
use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};

const MAX_MESSAGE: u64 = 64 * 1024;

#[derive(Serialize, Deserialize)]
struct Endpoint {
    port: u16,
    token: String,
}

#[derive(Serialize, Deserialize)]
struct Delivery {
    token: String,
    urls: Vec<String>,
}

pub struct Instance {
    _lock: File,
    pub links: async_channel::Receiver<Vec<String>>,
    stopped: Arc<AtomicBool>,
    listener: Option<JoinHandle<()>>,
}

impl Instance {
    /// A second launch forwards to the running process, including an empty launch to focus it.
    pub fn start(state: &Path, urls: Vec<String>) -> Result<Option<Self>> {
        std::fs::create_dir_all(state)?;
        let mut options = OpenOptions::new();
        options.create(true).truncate(false).read(true).write(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        let lock = options.open(state.join("desktop-instance.lock"))?;
        let endpoint_path = state.join("desktop-instance.json");
        match lock.try_lock() {
            Ok(()) => {}
            Err(TryLockError::WouldBlock) => {
                let deadline = Instant::now() + Duration::from_secs(2);
                loop {
                    if let Ok(endpoint) = read_endpoint(&endpoint_path)
                        && forward(endpoint, &urls).is_ok()
                    {
                        return Ok(None);
                    }
                    if Instant::now() >= deadline {
                        bail!("The running Tuist app is not ready to receive links. Try again.");
                    }
                    std::thread::sleep(Duration::from_millis(25));
                }
            }
            Err(TryLockError::Error(error)) => return Err(error.into()),
        }
        let listener = TcpListener::bind(("127.0.0.1", 0))?;
        listener.set_nonblocking(true)?;
        let mut token = [0; 32];
        getrandom::fill(&mut token).map_err(|error| anyhow::anyhow!("{error}"))?;
        let token = token
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect::<String>();
        let endpoint = Endpoint {
            port: listener.local_addr()?.port(),
            token: token.clone(),
        };
        let mut endpoint_file = options.truncate(true).open(endpoint_path)?;
        serde_json::to_writer(&mut endpoint_file, &endpoint)?;
        endpoint_file.flush()?;
        let (sender, links) = async_channel::bounded(16);
        sender.try_send(urls)?;
        let stopped = Arc::new(AtomicBool::new(false));
        let shutdown = stopped.clone();
        let listener = std::thread::spawn(move || {
            while !shutdown.load(Ordering::Relaxed) && !sender.is_closed() {
                let mut stream = match listener.accept() {
                    Ok((stream, _)) => stream,
                    Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                        std::thread::sleep(Duration::from_millis(25));
                        continue;
                    }
                    Err(_) => break,
                };
                let _ = stream.set_nonblocking(false);
                let _ = stream.set_read_timeout(Some(Duration::from_secs(1)));
                let _ = stream.set_write_timeout(Some(Duration::from_secs(1)));
                let mut bytes = Vec::new();
                if (&mut stream)
                    .take(MAX_MESSAGE + 1)
                    .read_to_end(&mut bytes)
                    .is_err()
                    || bytes.len() as u64 > MAX_MESSAGE
                {
                    continue;
                }
                if let Ok(delivery) = serde_json::from_slice::<Delivery>(&bytes)
                    && delivery.token == token
                    && delivery.urls.len() <= 16
                    && sender.try_send(delivery.urls).is_ok()
                {
                    let _ = stream.write_all(b"ok");
                }
            }
        });
        Ok(Some(Self {
            _lock: lock,
            links,
            stopped,
            listener: Some(listener),
        }))
    }
}

impl Drop for Instance {
    fn drop(&mut self) {
        self.stopped.store(true, Ordering::Relaxed);
        if let Some(listener) = self.listener.take() {
            let _ = listener.join();
        }
    }
}

fn read_endpoint(path: &Path) -> Result<Endpoint> {
    Ok(serde_json::from_reader(
        File::open(path)?.take(MAX_MESSAGE),
    )?)
}

fn forward(endpoint: Endpoint, urls: &[String]) -> Result<()> {
    let mut stream = TcpStream::connect_timeout(
        &std::net::SocketAddr::from(([127, 0, 0, 1], endpoint.port)),
        Duration::from_secs(2),
    )
    .context("Connect to the running Tuist app")?;
    stream.set_read_timeout(Some(Duration::from_secs(2)))?;
    stream.set_write_timeout(Some(Duration::from_secs(2)))?;
    let delivery = Delivery {
        token: endpoint.token,
        urls: urls.to_vec(),
    };
    let bytes = serde_json::to_vec(&delivery)?;
    if bytes.len() as u64 > MAX_MESSAGE || urls.len() > 16 {
        bail!("Too many or oversized navigation links");
    }
    stream.write_all(&bytes)?;
    stream.shutdown(Shutdown::Write)?;
    let mut ack = [0; 2];
    stream.read_exact(&mut ack)?;
    if &ack != b"ok" {
        bail!("Tuist did not accept the navigation links");
    }
    Ok(())
}

#[cfg(test)]
mod tests;
