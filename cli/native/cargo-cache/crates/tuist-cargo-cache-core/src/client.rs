//! Blocking client for the local cache-agent protocol.

use crate::{AGENT_PROTOCOL_VERSION, AgentRequest, AgentResponse};
use eyre::{Result, bail};
use std::io::{BufRead, BufReader, Read, Write};

/// A synchronous client over an already-connected local agent stream.
///
/// Embedders own endpoint discovery and platform transport creation; this type
/// owns the version handshake and newline-delimited protocol framing.
pub struct BlockingAgentClient<S> {
    stream: BufReader<S>,
}

impl<S> BlockingAgentClient<S>
where
    S: Read + Write,
{
    /// Negotiate the exact agent protocol and application version.
    pub fn connect(stream: S, client_version: impl Into<String>) -> Result<Self> {
        let mut client = Self {
            stream: BufReader::new(stream),
        };
        match client.request(AgentRequest::Hello {
            protocol: AGENT_PROTOCOL_VERSION,
            client_version: client_version.into(),
        })? {
            AgentResponse::Hello { protocol, .. } if protocol == AGENT_PROTOCOL_VERSION => {
                Ok(client)
            }
            AgentResponse::Error { message } => bail!(message),
            _ => bail!("cache agent returned an incompatible handshake"),
        }
    }

    /// Send one request and wait for its response.
    pub fn request(&mut self, request: AgentRequest) -> Result<AgentResponse> {
        serde_json::to_writer(self.stream.get_mut(), &request)?;
        self.stream.get_mut().write_all(b"\n")?;
        self.stream.get_mut().flush()?;
        let mut response = String::new();
        if self.stream.read_line(&mut response)? == 0 {
            bail!("cache agent closed the connection without a response");
        }
        Ok(serde_json::from_str(&response)?)
    }

    /// Begin a prediction-manifest run and return its opaque identifier.
    pub fn begin_task(&mut self, task: impl Into<String>) -> Result<String> {
        match self.request(AgentRequest::BeginTask { task: task.into() })? {
            AgentResponse::TaskBegun { run } => Ok(run),
            AgentResponse::Error { message } => bail!(message),
            _ => bail!("cache agent returned an unexpected begin-task response"),
        }
    }

    /// Commit predictions collected for a task run.
    pub fn commit_task(&mut self, run: impl Into<String>) -> Result<()> {
        match self.request(AgentRequest::CommitTask { run: run.into() })? {
            AgentResponse::TaskCommitted => Ok(()),
            AgentResponse::Error { message } => bail!(message),
            _ => bail!("cache agent returned an unexpected commit-task response"),
        }
    }

    /// Recover the connected stream.
    pub fn into_inner(self) -> S {
        self.stream.into_inner()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Cursor, Result as IoResult};

    struct ScriptedStream {
        responses: Cursor<Vec<u8>>,
        requests: Vec<u8>,
    }

    impl Read for ScriptedStream {
        fn read(&mut self, buffer: &mut [u8]) -> IoResult<usize> {
            self.responses.read(buffer)
        }
    }

    impl Write for ScriptedStream {
        fn write(&mut self, buffer: &[u8]) -> IoResult<usize> {
            self.requests.extend_from_slice(buffer);
            Ok(buffer.len())
        }

        fn flush(&mut self) -> IoResult<()> {
            Ok(())
        }
    }

    fn stream(responses: &[AgentResponse]) -> ScriptedStream {
        let mut bytes = Vec::new();
        for response in responses {
            serde_json::to_writer(&mut bytes, response).unwrap();
            bytes.push(b'\n');
        }
        ScriptedStream {
            responses: Cursor::new(bytes),
            requests: Vec::new(),
        }
    }

    #[test]
    fn begins_and_commits_task_runs() {
        let responses = [
            AgentResponse::Hello {
                protocol: AGENT_PROTOCOL_VERSION,
                agent_version: "0.5.1".into(),
            },
            AgentResponse::TaskBegun {
                run: "run-1".into(),
            },
            AgentResponse::TaskCommitted,
        ];
        let mut client = BlockingAgentClient::connect(stream(&responses), "0.5.1").unwrap();
        let run = client.begin_task("task-1").unwrap();
        client.commit_task(&run).unwrap();
        assert_eq!(run, "run-1");

        let written = String::from_utf8(client.into_inner().requests).unwrap();
        assert!(written.contains("\"type\":\"begin_task\""));
        assert!(written.contains("\"type\":\"commit_task\""));
    }

    #[test]
    fn rejects_a_different_protocol_version() {
        let responses = [AgentResponse::Hello {
            protocol: AGENT_PROTOCOL_VERSION + 1,
            agent_version: "0.5.1".into(),
        }];
        let error = BlockingAgentClient::connect(stream(&responses), "0.5.1")
            .err()
            .expect("protocol mismatch should fail");
        assert!(error.to_string().contains("incompatible handshake"));
    }
}
