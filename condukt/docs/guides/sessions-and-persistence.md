# Sessions and Persistence

Every running agent owns a `Condukt.Session`: the `GenServer` that holds
conversation history, tool configuration, and runtime options. By default
sessions live only for the lifetime of the process. A session store lets you
snapshot and restore them.

## Built-in stores

* `Condukt.SessionStore.Memory` keeps snapshots in ETS. Useful for restoring
  state within a running BEAM (for example after a `GenServer` crash).
* `Condukt.SessionStore.Disk` writes snapshots to disk. Useful for crashing
  recovery, deployments, and CLIs.
* `Condukt.SessionStore.ObjectStore` writes to S3 or a service compatible with
  it, such as Tigris, R2, or MinIO. Useful when a session moves between
  machines, as when a deployment replaces the one running it.

All three also keep a journal of the run in progress, so a run the process
dies in can be resumed. See [Resuming an interrupted run](#resuming-an-interrupted-run).

```elixir
# Restore within the current VM
{:ok, agent} =
  MyApp.CodingAgent.start_link(
    session_store: Condukt.SessionStore.Memory,
    session_store_key: {:coding_agent, "/tmp/project"}
  )

# Persist to disk across restarts
{:ok, agent} =
  MyApp.CodingAgent.start_link(
    cwd: "/tmp/project",
    session_store: Condukt.SessionStore.Disk
  )

# Custom path
{:ok, agent} =
  MyApp.CodingAgent.start_link(
    session_store: {Condukt.SessionStore.Disk, path: "/tmp/condukt.session"}
  )
```

When a store is configured, Condukt loads the snapshot at `start_link/1` and
saves a fresh snapshot after every completed run.

## Object storage

`Condukt.SessionStore.ObjectStore` only ever creates objects, using S3's
conditional writes (`If-None-Match: *`), so it needs no database next to the
bucket:

```elixir
bucket =
  {Condukt.SessionStore.ObjectStore.S3,
   endpoint: "https://t3.storage.dev",
   bucket: "sessions",
   access_key_id: System.fetch_env!("AWS_ACCESS_KEY_ID"),
   secret_access_key: System.fetch_env!("AWS_SECRET_ACCESS_KEY")}

{:ok, agent} =
  MyApp.CodingAgent.start_link(
    session_store: {Condukt.SessionStore.ObjectStore, bucket: bucket, key: "thread-42", epoch: lease.epoch}
  )
```

A save writes only the messages the run added, and each journal record is
one small object. Pass `:encrypt` and `:decrypt` functions to encrypt every
object before it leaves the process.

When something outside Condukt hands a session from one machine to another,
such as a lease in a database, pass the owner's `:epoch`, which must grow
with every new owner. The new owner's first call fences the store, and every
later write from an older epoch fails with `{:error, :fenced}`, so a process
that lost its session but is still running cannot write over the new one.
The module documentation describes the layout and the protocol.

## Store keys and options

Condukt passes `:agent_module`, `:cwd`, an optional `:id`, an optional `:key`,
and any `:session_store_opts` to every store callback. Use
`:session_store_key` when persistence should follow an application domain key
instead of the generated session identifier:

```elixir
{:ok, agent} =
  MyApp.CodingAgent.start_link(
    session_store: MyApp.RedisStore,
    session_store_key: "telegram-chat:123",
    session_store_opts: [redix: MyApp.Redix]
  )
```

Stores receive that key as `opts[:key]`. If `:session_store` is passed as a
`{module, opts}` tuple, those tuple options are merged last and can override
the defaults for that store.

## What a snapshot contains

`Condukt.SessionStore.Snapshot` captures the parts of the session that need
to survive a restart: the message history and the configurable options (such
as model, system prompt, and `cwd`). It holds finished runs only; the run in
progress lives in the store's journal until it ends.

Assistant history retains opaque provider reasoning details separately from visible
text and thinking summaries. They round-trip through ReqLLM and version-3 snapshots,
including across tool calls. Protect stored snapshots as sensitive conversation data;
provider encryption is not a replacement for the store's access controls. Version-1
and version-2 snapshots still load without inventing missing reasoning state.

The journal bookkeeping below, which runs a snapshot holds and the outcomes
of recent request ids, is not a snapshot field. Stores that decode snapshots
with `:erlang.binary_to_term(binary, [:safe])`, as the disk store does, refuse
a key the running build has never seen, so a new field would cost a process
on an earlier release, as during a rolling deploy or a rollback, the whole
snapshot. The bookkeeping sits under a string key, encoded on its own, and
`Condukt.SessionStore.Snapshot.runs/1` reads it. An earlier release reads such
a snapshot and drops the bookkeeping when it saves, which forgets the stored
outcomes of request ids. A store that writes snapshots field by field rather
than as one term must keep that entry; the conformance suite checks it.

## Resuming an interrupted run

A snapshot is written once per run, so on its own a crash loses the run the
process died in: the prompt, the model responses, and the tool calls that
already took effect. A store that keeps a journal closes that gap. While a run
is in progress the session appends one small record per step, each stored
before the step is shown to subscribers or acted on:

1. the prompt, when the run starts;
2. each model response;
3. each tool call's intent, before the tool runs;
4. each tool result, as soon as that call finishes, even while other calls of
   the same round are still running;
5. steering messages (`Condukt.steer/2`), when they join the run;
6. the compacted history, when background compaction replaces it mid-run.

The history is not rewritten on every step. When the run ends the session
records how it ended, saves the snapshot, and then clears the journal. If that
save fails the journal is kept, and a later restart restores the run as
finished, with the outcome it ended with, rather than interrupted.

A step whose record cannot be stored does not happen. A tool whose intent the
store refuses is not run, and the model gets an error result saying so; a run
whose prompt or model response cannot be stored ends with
`{:error, {:journal_failed, reason}}`. A tool result that cannot be stored
does not stop the run, but after a crash that call counts as interrupted.

A journal is only replayed onto the history it was written against. The
prompt's record carries a fingerprint of the history the run started from, and
a journal whose first run does not match the snapshot, as after restoring an
older snapshot from a backup, is ignored with a warning.

A session whose store holds a journal it cannot read does not start: it
returns `{:error, {:journal_load_failed, reason}}`. Starting without the
journal would hide an unfinished run and reuse its run ids, so a later
recovery would merge the two runs.

### Resuming is the caller's decision

A session never continues a run on its own. When a session starts on a store
whose journal holds an unfinished run, it reports the run as interrupted.
`Condukt.history/1` shows the history before that run until it is resumed or
given up; finished runs whose snapshot failed to save are already part of it.

A run stops when its session process exits. Its worker runs under the
session's own task supervisor, which shuts it down, killing it after 100 ms
if it does not stop; that closes the provider request and stops the tool
processes. Work a tool handed to something outside the session can still
finish: a command in a remote sandbox, a call on an MCP server, a native
sandbox call already running, or a process that traps exits. Treat those as
possibly still in progress when you decide whether to resume.

A worker can also die while its session lives, for example when a tool exits
it. The call then ends with `{:error, {:turn_crashed, reason}}` and the session
takes new runs. A journaled run is left interrupted, as after a restart, so
`resume/2` or a retry of its request id continues it; any other run fails with
that error.

```elixir
{:ok, agent} =
  MyApp.CodingAgent.start_link(
    cwd: "/tmp/project",
    session_store: Condukt.SessionStore.Disk
  )

case Condukt.Session.interrupted(agent) do
  nil -> :ok
  %{run_id: _, request_id: _, restarts: _} -> Condukt.Session.resume(agent)
end
```

`Condukt.Session.resume/2` accepts `:timeout` and `:trace_context`, keeps the
`:max_turns` the run started with, and returns the run's result like
`Condukt.run/3`. It picks up after the last stored step:

* A model request the process died during is made again.
* A final answer that was stored but never returned is returned.
* A tool call that never started runs.
* Results that were stored are kept, and put back in the order the model asked
  for the calls.
* A tool call whose intent was stored but whose result was not may already
  have taken effect. It runs again only when its tool declared itself
  replay-safe when the call ran and still does on resume, so a release that
  marks a tool replay-safe never reruns a call made before it. Otherwise the
  model gets an error result saying the call was interrupted and was not run
  again, and decides what to do next.

`Condukt.Session.resume_stream/2` does the same and returns the events of
`Condukt.stream/3` instead of a result, whichever way the run started:

```elixir
agent
|> Condukt.Session.resume_stream()
|> Enum.each(fn
  {:text, chunk} -> IO.write(chunk)
  {:tool_result, id, result} -> IO.inspect(result, label: id)
  _event -> :ok
end)
```

Results the resume decides without the model, a rerun call's or an
interrupted call's error, are emitted as `{:tool_result, id, result}` before
the run goes on. A final answer that was stored but never delivered is
emitted as one `{:text, answer}`. Events for stored steps are not sent
again, but a response the process died while receiving is requested again,
so its text is streamed again. A stream that cannot start emits
`{:error, reason}` and ends: `:nothing_to_resume`, `:already_streaming`,
`{:restart_limit, count}`, or `{:journal_failed, reason}`. Any stream whose
session process dies before it finishes emits
`{:error, {:session_exit, reason}}` and ends, so a subscriber can resume from a
new process.

A resume that cannot store its own record, which is what counts restarts,
returns `{:error, {:journal_failed, reason}}` and leaves the run interrupted.

Starting a new run instead of resuming gives the interrupted run up. What it
stored, its prompt included, stays in the history, with an interrupted result
for every tool call left without one, so the model sees it on the next request.
Aborting a resumed run keeps the same, and drops only what the resume itself did.

### Replay-safe tools

A tool is replay-safe when running the same call twice leaves the world as
running it once. `Condukt.Tools.Read`, `Glob`, `Grep`, and `Write` declare it;
`Bash`, `Edit`, `Command`, and MCP tools do not, since running them twice can
do something different from running them once. `Bash` can opt in with
`{Condukt.Tools.Bash, replay_safe: true}` on a sandbox whose processes outlive
the session's node: a rerun call follows the command its interrupted call
started instead of starting it again.

```elixir
defmodule MyApp.Tools.FetchInvoice do
  use Condukt.Tool

  @impl true
  def replay_safe?, do: true

  # ...
end

Condukt.tool(name: "lookup", description: "...", parameters: %{}, call: &lookup/2, replay_safe: true)
```

A tool with external effects can still be made replay-safe by giving the
effect its own idempotency key, for example one derived from the session id
and the arguments, so that the provider ignores the second call.

### Request ids

Pass `:request_id` to make a submission run at most once:

```elixir
Condukt.run(agent, "Deploy the release", request_id: "deploy-2026-11-14")
```

A retry with the same id, from the same process or after a restart, gets the
outcome of the first submission instead of running it again. When the first
submission is the run the previous process died in, the retry resumes it,
using the prompt the run stored. Outcomes are kept for the session's 50 most
recent request ids, in the snapshot. That needs a session store but not a
journal, and covers runtime-backed agents too; without a store, outcomes last
only as long as the session process.

The outcome is how the run ended: `{:ok, answer}`, or `{:error, reason}` for a
run that failed, was aborted, or was given up by starting another run. The
first caller gets the reason as it happened; a retry gets it as stored, where
a reason that is not an atom becomes its description, with the session's
secrets removed, since a raw reason can hold terms a freshly started node
cannot decode and, for a provider error, the whole conversation. Retry with a
new id to try again. `Condukt.stream/3` records its outcome under its
`:request_id` the same way: a stream retrying the interrupted run's request id
resumes it, streaming, and a stream for a request that already finished emits
its stored outcome, `{:text, answer}` or `{:error, reason}`, without running.

### Restart limit

Work that crashes its process before it reaches the next step, for example by
exhausting memory, would crash again on every resume. Each resume is counted,
and the count resets whenever the run stores a new step. Once a run has been
resumed `:restart_limit` times in a row without progress, the next resume ends
it with `{:error, {:restart_limit, count}}` instead of running it again. The
default is 5; pass `restart_limit: n` when starting the session, set
`config :condukt, restart_limit: n`, or use `:infinity` to never give up.

### What the journal does not cover

* Only the native agent loop is journaled. Runtime-backed agents such as
  `Condukt.AgentRuntimes.Codex` own their loop, and keep the snapshot-only
  behaviour apart from request ids.
* A parked tool call (see the [Parking guide](parking.md)) stores its intent
  when it first runs and its result when it wakes and finishes. What it waits
  for is not stored, so a run interrupted while a call is parked resumes with
  that call interrupted, or run again from the start when its tool is
  replay-safe. Signals sent to the process that died are lost.
* A tool's partial output is not stored, only its result. Streamed text is
  shown before the response it belongs to is complete and stored; a crash
  mid-stream makes the whole request again on resume.
* Durability is the store's. `Condukt.SessionStore.Disk` survives the process
  dying but does not `fsync`, so the newest records can be lost on power
  failure. `Condukt.SessionStore.Memory` survives the session process but not
  the virtual machine.
* One process writes a session's store at a time. Start a session on a store
  only after the previous process for it has exited, or give each new owner
  a higher `:epoch` on `Condukt.SessionStore.ObjectStore`, which refuses the
  previous owner's writes.

## Implementing a store

Implement the `Condukt.SessionStore` behaviour:

```elixir
defmodule MyApp.RedisStore do
  @behaviour Condukt.SessionStore

  @impl true
  def load(opts) do
    redix = Keyword.fetch!(opts, :redix)

    case Redix.command(redix, ["GET", key(opts)]) do
      {:ok, nil} -> :not_found
      {:ok, blob} -> {:ok, :erlang.binary_to_term(blob)}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def save(snapshot, opts) do
    redix = Keyword.fetch!(opts, :redix)
    Redix.command(redix, ["SET", key(opts), :erlang.term_to_binary(snapshot)])
    :ok
  end

  @impl true
  def clear(opts) do
    redix = Keyword.fetch!(opts, :redix)
    Redix.command(redix, ["DEL", key(opts)])
    :ok
  end

  defp key(opts), do: "condukt:" <> Keyword.fetch!(opts, :key)
end
```

To make runs resumable, also implement `append_journal/2`, `load_journal/1`,
and `clear_journal/1`. A journal holds opaque records that must come back in
the order they were appended; a Redis list fits:

```elixir
@impl true
def append_journal(records, opts) do
  redix = Keyword.fetch!(opts, :redix)
  entries = Enum.map(records, &:erlang.term_to_binary/1)

  case Redix.command(redix, ["RPUSH", journal_key(opts) | entries]) do
    {:ok, _length} -> :ok
    {:error, reason} -> {:error, reason}
  end
end

@impl true
def load_journal(opts) do
  redix = Keyword.fetch!(opts, :redix)

  with {:ok, entries} <- Redix.command(redix, ["LRANGE", journal_key(opts), "0", "-1"]) do
    {:ok, Enum.map(entries, &:erlang.binary_to_term/1)}
  end
end

@impl true
def clear_journal(opts) do
  redix = Keyword.fetch!(opts, :redix)

  with {:ok, _} <- Redix.command(redix, ["DEL", journal_key(opts)]), do: :ok
end

defp journal_key(opts), do: key(opts) <> ":journal"
```

`Condukt.SessionStore.Conformance` runs the tests every store has to pass,
including the journal's, from the store's own test suite:

```elixir
defmodule MyApp.RedisStoreTest do
  use ExUnit.Case, async: true
  use Condukt.SessionStore.Conformance, store: MyApp.RedisStore

  setup do
    prefix = "test:#{System.unique_integer([:positive])}"

    %{
      store_opts: [redix: MyApp.Redix, key: prefix <> ":a"],
      other_store_opts: [redix: MyApp.Redix, key: prefix <> ":b"]
    }
  end
end
```

Pass `journal: false` for a store that only keeps snapshots. Such a store
keeps working as before: sessions restore its snapshot and lose the run they
die in.

Then plug it into the agent:

```elixir
MyApp.CodingAgent.start_link(
  session_store: MyApp.RedisStore,
  session_store_key: "user:42",
  session_store_opts: [redix: MyApp.Redix]
)
```

## Clearing history

`Condukt.clear/1` resets the conversation. If a session store is configured,
Condukt also calls the store's `clear/1` callback, and `clear_journal/1` when
it keeps a journal, so persisted state is removed. Request ids and any
interrupted run are forgotten with it. When the journal cannot be cleared,
Condukt saves an empty snapshot that covers its runs instead of removing the
snapshot, so a restart does not bring them back.
