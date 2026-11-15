# Waiting for Events

Some tools wait for something outside the session: a CI build's webhook, a
person's answer to a question, a slow job that has to be polled.

A process blocked in `receive` costs almost nothing, so the problem with
waiting inside `call/2` is not the process. It is that the wait is invisible:
the tool timeout cuts it off after five minutes, nothing outside knows where
to deliver the event or what to do with one that arrives early or twice, and a
process's stack cannot be saved, so a restart loses the wait.

Such a tool **parks** instead. Like a `GenServer` callback returning
`{:noreply, state, timeout}`, it returns `{:park, state, opts}` in place of a
result, saying what wakes it: signals delivered from outside, a deadline, or
both. The wait becomes data the session holds. No tool code runs meanwhile
and the tool timeout does not apply; the turn's worker blocks until a call
wakes. The session then calls the tool's `wake/3` with the event and `state`,
and the turn continues with what it returns.

## Parking a tool call

```elixir
defmodule MyApp.Signals.CiResult do
  @behaviour Condukt.Signal

  @impl true
  def cast(%{"status" => status, "log_url" => url}) when status in ["passed", "failed"],
    do: {:ok, %{status: status, log_url: url}}

  def cast(_value), do: {:error, :expected_status_and_log_url}
end

defmodule MyApp.Tools.RunCi do
  use Condukt.Tool

  alias MyApp.Signals.CiResult

  @impl true
  def name, do: "run_ci"

  @impl true
  def description, do: "Runs CI on a git ref and reports the result"

  @impl true
  def parameters do
    %{type: "object", properties: %{ref: %{type: "string"}}, required: ["ref"]}
  end

  @impl true
  def call(%{"ref" => ref}, context) do
    key = "ci-" <> context.tool_call_id
    # Register the webhook before triggering, so a fast one finds this call.
    MyApp.Webhooks.expect(context.session_id, CiResult, key)
    {:ok, build} = MyApp.CI.trigger(ref, idempotency_key: key)

    {:park, %{build_id: build.id}, signals: [{CiResult, key}], timeout: :timer.hours(2)}
  end

  @impl true
  def wake({:signal, {CiResult, _key}, %{status: "passed", log_url: url}}, _state, _context),
    do: {:ok, "CI passed: #{url}"}

  def wake({:signal, {CiResult, _key}, %{log_url: url}}, _state, _context),
    do: {:error, "CI failed: #{url}"}

  def wake(:timeout, %{build_id: id}, _context),
    do: {:error, "CI build #{id} never reported"}

  @impl true
  def cancel(%{build_id: id}, _context), do: MyApp.CI.cancel(id)
end
```

`{:park, state, opts}` takes any term as `state` and these options:

* `:signals` - `{kind, key}` pairs to wake on. `kind` is a `Condukt.Signal`
  module and `key` a string. The first one delivered wakes the call.
* `:timeout` - milliseconds from now after which the call wakes anyway, or
  `:until`, a `DateTime`.

`wake/3` receives `{:signal, {kind, key}, value}`, with the value `cast/1`
returned, or `:timeout` when the deadline came first. It returns what `call/2`
returns, so a woken call may park again, for example to poll once more.

Inline tools park the same way and take `:wake` and `:cancel` functions next
to `:call`.

### Rules

* A park needs signals, a deadline, or both, and the tool must implement
  `wake/3`. Otherwise the call ends with an `{:error, {:invalid_park, reason}}`
  result, which the model sees.
* Keys belong to the session, so put the tool call id in each key.
* Each key serves one wait. The wake that uses a key consumes it and closes
  the wait's other keys, and a later park on any of them fails with
  `{:invalid_park, {:signal_key_used, key}}`. A second wait for the same kind
  of event uses a new key, such as `ci-1`, `ci-2`.
* Other calls in the same round run as usual. Their results are kept, and the
  model sees the whole round once every call has a result.
* Parks belong to the turn. When the turn ends, its keys close, and they stay
  closed in later turns of the session.

## Delivering signals

Whatever receives the outside event, such as a webhook controller or an inbox
UI, delivers it with `Condukt.signal/4`:

```elixir
def ci_webhook(conn, %{"session" => session_id, "key" => key} = params) do
  value = Map.take(params, ["status", "log_url"])

  case Condukt.signal(session_id, MyApp.Signals.CiResult, key, value) do
    :ok -> send_resp(conn, 202, "")
    {:error, :duplicate} -> send_resp(conn, 200, "")
    {:error, :closed} -> send_resp(conn, 410, "")
    {:error, {:invalid, _reason}} -> send_resp(conn, 422, "")
    {:error, :not_found} -> send_resp(conn, 404, "")
  end
end
```

The first argument is a session pid or name, or the id of a session started
with `Condukt.Sessions`. Which sessions an id reaches depends on the
`Condukt.Sessions.Registry` adapter: the default sees the local node only, and
`Condukt.Sessions.Registry.PG` sees every connected node, so a webhook can land
on any node of a cluster:

```elixir
config :condukt, session_registry: Condukt.Sessions.Registry.PG
```

`Condukt.Sessions.Registry.Horde` does the same on `Horde.Registry`, with the
optional `:horde` dependency. Other adapters, such as one on `:syn`, implement
the same behaviour. `cast/1` of the signal kind checks the value in the
calling process. The result is `:ok` or one of these errors:

| Error | Meaning |
| --- | --- |
| `:duplicate` | The key already holds a value, as for a webhook retry. |
| `{:invalid, reason}` | `cast/1` rejected the value. Nothing is kept. |
| `:closed` | No turn is running, or the key's wait is over: its deadline came first, another of its keys woke it, or its turn ended. |
| `:inbox_full` | The turn already holds 100 signals for keys no call has parked on. |
| `:not_found` | No session answers under that name. |

Treat `:duplicate` and `:closed` as final answers to the sender. Nothing
checks who sends a signal, so authenticate senders before delivering.

A signal that arrives while the turn runs but before the call has parked, such
as a webhook faster than the tool, is kept. The park then wakes at once.

## Waiting for a person

An approval with a deadline parks on one key with a timeout:

```elixir
Condukt.tool(
  name: "ask",
  description: "Asks a person a question",
  parameters: %{type: "object", properties: %{question: %{type: "string"}}},
  call: fn %{"question" => question}, context ->
    key = "answer-" <> context.tool_call_id
    MyApp.Inbox.ask(context.session_id, key, question)
    {:park, nil, signals: [{MyApp.Signals.Answer, key}], timeout: :timer.hours(4)}
  end,
  wake: fn
    {:signal, _key, answer}, nil, _context -> {:ok, answer}
    :timeout, nil, _context -> {:error, "nobody answered within four hours"}
  end
)
```

A late answer after the deadline gets `{:error, :closed}`.

## Polling with backoff

A tool waiting on a slow job parks on time alone and carries its progress in
its state:

```elixir
call: fn %{"name" => name}, _context -> poll(%{job: MyApp.Jobs.start(name), delay: 500}) end,
wake: fn :timeout, state, _context -> poll(state) end

defp poll(%{job: job, delay: delay} = state) do
  case MyApp.Jobs.status(job) do
    :done -> {:ok, "#{job} is done"}
    :running -> {:park, %{state | delay: min(delay * 2, 60_000)}, timeout: delay}
  end
end
```

## Seeing what a session waits for

`Condukt.Session.waiting/1` returns `nil` while a turn runs or the session is
idle. Once every pending call is parked it returns:

```elixir
%{
  tool_calls: [
    %{tool_call_id: "call_1", tool: "run_ci", signals: [{MyApp.Signals.CiResult, "ci-call_1"}], until: ~U[...]}
  ],
  wake_at: ~U[...]
}
```

`wake_at` is the earliest deadline, or `nil` when only signals can wake the
turn. The session publishes the same map as a `{:waiting, map}` event to
stream subscribers and the notifier whenever it changes, so a host learns the
next wake time without polling.

While the session process lives, it arms the deadlines with
`Process.send_after/3`. A host that stops idle sessions can schedule its own
wake-up from `wake_at` instead.

## Callers of a parked turn

A parked turn is still the running turn: `Condukt.run/3` keeps waiting for its
answer, a stream stays open, new prompts get `{:error, :already_streaming}`,
and steering waits for the next model request. Pass a longer `:timeout` when a
caller should wait out a long park, or let a notifier report the outcome. By
default `run/3` gives up after five minutes with
`{:error, {:session_exit, :timeout}}` while the turn goes on, and `stream/3`
emits `{:error, :timeout}` each time five minutes pass without an event and
keeps waiting.

## Cancelling

`Condukt.abort/1` and `Condukt.clear/1` end a parked turn like a running one.
They call the optional `cancel/2` of each parked call, and of each woken call
still running, with the state it last parked with, much as a `GenServer`'s
`terminate/2` receives its state. Each runs in its own process. `cancel/2` may
run more than once, so keep it idempotent. Signals for the aborted turn then
get `{:error, :closed}`.

`Condukt.Sessions.stop/1` aborts the turn before stopping the session, and a
session stopped with `GenServer.stop/1` cancels its parked calls as it
terminates. A session that crashes or is killed runs no `cancel/2`, so find
external work a lost session started by its idempotency key.

## Gates in front of a tool

The session parks a call wherever its outcome is `{:park, state, opts}`, and
routes the wake to the `wake/3` of the tool spec it ran. A gate in front of a
tool, such as an approval, wraps the tool: its `call` parks with a state that
marks the gate's own wait, and its `wake` handles that event before calling
the wrapped tool, which may park in turn.

## Durability

Parked calls, early signals, and used keys live in the session process for
now. A session that stops or crashes while parked loses its waits. Every change
to them goes through one step in the session as a list of records
(`{:park, ...}`, `{:signal, ...}`, `{:timeout, ...}`, `{:done, ...}`,
`:end_turn`), which
is where a durable turn journal stores them so that a restarted session can
resume the wait.

Only native agent loops park. A tool that returns `{:park, state, opts}` under
another runtime returns an error to that runtime.
