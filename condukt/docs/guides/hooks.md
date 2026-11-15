# Hooks

Hooks let you step into the native agent loop without writing a tool or a
runtime. A hook can stop a tool call before it runs, change its arguments,
replace its result, or send the model back to work when it would end the run.

To only observe a run, use `handle_event/2`, a notifier, or the
`[:condukt, :llm_turn, :stop]` telemetry event. Use a hook when you need to
change what the loop does.

## Declaring hooks

A hook is a module that implements any of the optional callbacks of
`Condukt.Hooks`. An agent lists its hooks in `hooks/0`, as modules or
`{module, opts}` tuples:

```elixir
defmodule MyApp.Coder do
  use Condukt

  @impl true
  def tools, do: [Condukt.Tools.Read, Condukt.Tools.Edit, Condukt.Tools.Bash]

  @impl true
  def hooks, do: [MyApp.Hooks.Timeout, {MyApp.Hooks.Approval, tools: ["Bash"]}]
end
```

The `:hooks` session option replaces the agent's list, for example in a test
or a one-shot run:

```elixir
Condukt.run(MyApp.Coder, "Fix the failing test.", hooks: [MyApp.Hooks.Review])
```

Every callback receives a context map: the same context a tool gets, such as
`:session_id`, `:agent_module`, `:sandbox`, and `:assigns`, with `:opts` set
to the hook's own options. In `before_tool/2` and `after_tool/3`,
`:tool_call_id` is the call's id. `on_yield/2` gets `:tool_call_id` set to
`nil`, and also `:messages`, the run's history so far, `:turn`, the number of
model responses before this one in the run, and the run's `:max_turns`.

Hooks run only in the native loop. Runtimes such as
`Condukt.AgentRuntimes.Codex` own their loop and do not call them.

## The callbacks

| Callback | When it runs | Return |
| -------- | ------------ | ------ |
| `before_tool(call, context)` | Before a tool call executes | `:ok`, `{:rewrite, args}`, or `{:block, reason}` |
| `after_tool(call, result, context)` | After every tool call | `:ok` or `{:replace, result}` |
| `on_yield(message, context)` | When the model answers without tool calls | `:ok` or `{:continue, text}` |

`call` is `%{id: id, name: name, args: args}`. `result` is `{:ok, value}` or
`{:error, reason}`, after session secrets were redacted from it. Block
reasons, replaced results, and the text of a failed hook are redacted too
before the model or the history sees them.

## How the chain runs

Hooks run in the order they are listed, and each kind of callback forms its
own chain:

- **`before_tool`**: a `{:rewrite, args}` passes the new arguments to the next
  hook, and the call runs with the last ones. The first `{:block, reason}`
  stops the chain; the tool does not run, and the model gets
  `{:error, "Tool call blocked: " <> reason}` as the call's result.
- **`after_tool`**: a `{:replace, result}` passes the new result to the next
  hook, and the model gets the last one. A replaced `{:ok, value}` must be a
  string or encode as JSON, like a tool's result; otherwise the hook fails.
  It runs for every call, including
  calls a hook blocked or a failed `before_tool` stopped, and calls to unknown
  tools, and sees the arguments the call ran with. It does not run for a call
  stopped because the run was aborted. A call that parks, as described in
  [Waiting for Events](parking.md), runs `before_tool` once, before it first
  runs, and `after_tool` once, on its final result after the last wake. A
  rewrite is not kept across the park, so that `after_tool` sees the
  arguments the model sent; the tool's own parked state carries what it
  needs to finish.
- **`on_yield`**: the first `{:continue, text}` stops the chain. `text` is
  added to the history as a user message, and the model takes another turn in
  the same run. `Condukt.run/3` returns only the answer that stands, but a
  stream has already delivered the rejected answer's text events. Continued
  turns count against the run's `:max_turns`, and on the run's last turn the
  hooks are not asked: the answer stands.

## Processes, crashes, and aborts

Each tool call runs in its own process, linked below the turn's worker, and
each hook chain runs in a process of its own, linked below the work it
decides. Processes are cheap, so a hook that waits for a person simply waits,
with `receive`. Without hooks, a session runs one tool call per scheduler at
a time. With hooks, every call in a model response runs at once, up to 64, so
a waiting hook holds up nothing but its own call. Beyond 64, later calls wait
for a slot, and calls held by waiting hooks keep theirs.

- **Crashes fail their own unit.** A hook that raises, exits, or returns
  anything else ends its chain. A failed `before_tool` blocks the call, a
  failed `after_tool` gives the model an error result, and a failed `on_yield`
  leaves the answer standing. The model gets the failure's message, never a
  stack trace, and the crash is logged. A tool that crashes fails its own
  call; the run goes on.
- **An abort stops the hooks.** Aborting a run shuts down the turn's worker
  and every process linked below it, waiting hooks included. A waiting hook
  needs no abort handling, and a call is never admitted after the abort.
  Running tools stop too, except a tool declared with `on_abort: :finish`,
  which runs to its end; its `after_tool` hooks do not run.
- **A wait brings its own deadline.** The session's tool timeout, 5 minutes,
  bounds only the tool's own execution. A tool past it is killed, along with
  what it started and linked, such as a sub-agent session, and the model gets
  `{:error, :timeout}`. A hook bounds its own wait with `receive ... after`.
  `Condukt.run/3` has its own `:timeout`, also 5 minutes by default, so pass a
  longer one when hooks may wait for a person. `Condukt.stream/3` emits
  `{:error, :timeout}` each time its `:timeout`, also 5 minutes by default,
  passes without an event, so pass a longer one there too, or do not treat
  that event as the end of the run.
- **Sub-agents cannot wait long.** A foreground sub-agent runs inside its
  parent's `subagent` tool call, so the parent's 5-minute tool timeout bounds
  the whole child run, its hooks included, as does the child's own run
  timeout. Put gates that wait on people in the top-level agent.

## State lives in processes

A hook module holds no state between calls. State that outlives one call,
such as pending approvals, decisions, budgets, or rate limits, belongs in a
process in your supervision tree that the hook sends messages to. That
process can monitor the hook that asked, so a question disappears when an
abort stops the hook.

Hooks do not survive a session restart yet, because runs do not. When they
do, that process is where decisions are stored, keyed by session and tool
call id, so a resumed call that asks again gets the stored answer.

## Examples

### An approval gate

Ask a person before a risky command runs. The hook blocks in its own process
until `MyApp.Approvals` answers or its deadline passes:

```elixir
defmodule MyApp.Hooks.Approval do
  @behaviour Condukt.Hooks

  @impl true
  def before_tool(%{name: name} = call, context) do
    if name in Keyword.get(context.opts, :tools, []) do
      case MyApp.Approvals.ask(context.session_id, call, :timer.minutes(30)) do
        :approved -> :ok
        :denied -> {:block, "a person did not approve this call"}
        :timeout -> {:block, "nobody answered within 30 minutes"}
      end
    else
      :ok
    end
  end
end
```

`MyApp.Approvals` is a `GenServer` that keeps the pending questions and
monitors each asking process:

```elixir
defmodule MyApp.Approvals do
  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  # Runs in the hook's process and waits there for the answer.
  def ask(session_id, call, timeout) do
    question = GenServer.call(__MODULE__, {:ask, self(), session_id, call})

    receive do
      {:answer, ^question, answer} -> answer
    after
      timeout ->
        GenServer.cast(__MODULE__, {:withdraw, question})
        :timeout
    end
  end

  # Called by whatever shows the question, such as a LiveView.
  def answer(question, answer) when answer in [:approved, :denied] do
    GenServer.cast(__MODULE__, {:answer, question, answer})
  end

  @impl true
  def init(pending), do: {:ok, pending}

  @impl true
  def handle_call({:ask, hook, session_id, call}, _from, pending) do
    question = Process.monitor(hook)
    Phoenix.PubSub.broadcast(MyApp.PubSub, "approvals", {:asked, question, session_id, call})
    {:reply, question, Map.put(pending, question, hook)}
  end

  @impl true
  def handle_cast({:answer, question, answer}, pending) do
    {hook, pending} = Map.pop(pending, question)
    if hook, do: send(hook, {:answer, question, answer})
    Process.demonitor(question, [:flush])
    {:noreply, pending}
  end

  def handle_cast({:withdraw, question}, pending) do
    Process.demonitor(question, [:flush])
    {:noreply, Map.delete(pending, question)}
  end

  # The hook is gone, usually because its run was aborted.
  @impl true
  def handle_info({:DOWN, question, :process, _hook, _reason}, pending) do
    {:noreply, Map.delete(pending, question)}
  end
end
```

Approval binds to the arguments the hook saw. A hook listed after it that
rewrites the arguments runs the call with arguments nobody approved, so list
gates last.

### Rewriting arguments

Give shell commands a timeout when the model left it out:

```elixir
defmodule MyApp.Hooks.Timeout do
  @behaviour Condukt.Hooks

  @impl true
  def before_tool(%{name: "Bash", args: args}, _context) do
    {:rewrite, Map.put_new(args, "timeout", 60)}
  end

  def before_tool(_call, _context), do: :ok
end
```

### Trimming results

Shorten long outputs before the model reads them:

```elixir
defmodule MyApp.Hooks.Trim do
  @behaviour Condukt.Hooks

  @impl true
  def after_tool(_call, {:ok, output}, _context) when is_binary(output) and byte_size(output) > 20_000 do
    {:replace, {:ok, binary_part(output, 0, 20_000) <> "\n[output truncated]"}}
  end

  def after_tool(_call, _result, _context), do: :ok
end
```

### A review before the answer stands

Send the model back once to check its work. `context.turn` lets the hook bound
its own loop; continued turns also count against the run's `:max_turns`:

```elixir
defmodule MyApp.Hooks.Review do
  @behaviour Condukt.Hooks

  @impl true
  def on_yield(message, %{turn: turn}) do
    if turn < 10 and not reviewed?(message) do
      {:continue, "Review your answer against the request, fix what is wrong, and start your reply with REVIEWED."}
    else
      :ok
    end
  end

  defp reviewed?(message), do: String.starts_with?(Condukt.Message.text(message), "REVIEWED")
end
```

### Tests after edits

Run the project's tests when the model ends a stretch of work that edited
files, and send it back with the failures:

```elixir
defmodule MyApp.Hooks.TestsAfterEdits do
  @behaviour Condukt.Hooks

  alias Condukt.Message

  @impl true
  def on_yield(_message, %{messages: messages, sandbox: sandbox, turn: turn}) do
    with true <- turn < 20,
         true <- edited_since_last_user_message?(messages),
         {:ok, %{exit_code: code, output: output}} when code != 0 <- Condukt.Sandbox.exec(sandbox, "mix test") do
      {:continue, "The tests failed:\n\n#{output}\n\nFix them."}
    else
      _ -> :ok
    end
  end

  defp edited_since_last_user_message?(messages) do
    messages
    |> Enum.reverse()
    |> Enum.take_while(&(&1.role != :user))
    |> Enum.filter(&(&1.role == :assistant))
    |> Enum.flat_map(&Message.tool_calls/1)
    |> Enum.any?(fn {_id, name, _args} -> name in ["Edit", "Write"] end)
  end
end
```

After a continue, the last user message is the hook's own, so the tests run
again only when the fix edited files.
