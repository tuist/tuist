# Streaming and Events

`Condukt.run/3` waits for the agent loop to finish and returns the final
response. `Condukt.stream/3` returns a lazy `Stream` of events, which is the
right shape for chat UIs, LiveView, Phoenix Channels, and CLI output.

## Event vocabulary

| Event | Description |
| ----- | ----------- |
| `:agent_start` | The agent began processing this prompt. |
| `:turn_start` | A new LLM turn is starting. |
| `{:text, chunk}` | A chunk of model text. |
| `{:thinking, chunk}` | A chunk of model reasoning (if the provider exposes it). |
| `{:tool_call, name, id, args}` | The model is calling a tool. |
| `{:tool_result, id, result}` | A tool returned a result. |
| `:turn_end` | The current LLM turn finished. |
| `:agent_end` | The agent stopped its loop. |
| `{:error, reason}` | An error occurred during the run. |
| `{:subagent, tool_call_id, event}` | An event from a sub-agent the tool call started. See [Sub-agents](subagents.md#streaming-child-events). |
| `:done` | The stream is complete. Always the last event. |

## Streaming to stdout

```elixir
agent
|> Condukt.stream("Explain OTP")
|> Enum.each(fn
  {:text, chunk} -> IO.write(chunk)
  {:thinking, chunk} -> IO.write(IO.ANSI.faint() <> chunk <> IO.ANSI.reset())
  {:tool_call, name, _id, args} -> IO.inspect({name, args}, label: "tool")
  {:tool_result, _id, result} -> IO.inspect(result, label: "result")
  {:error, reason} -> IO.puts("Error: #{inspect(reason)}")
  :done -> IO.puts("\n[done]")
  _ -> :ok
end)
```

## Phoenix LiveView

A common pattern is to stream events from a `Task` and forward them to the
LiveView process:

```elixir
def handle_event("ask", %{"prompt" => prompt}, socket) do
  parent = self()

  Task.start_link(fn ->
    socket.assigns.agent
    |> Condukt.stream(prompt)
    |> Enum.each(&send(parent, {:agent_event, &1}))
  end)

  {:noreply, assign(socket, response: "")}
end

def handle_info({:agent_event, {:text, chunk}}, socket) do
  {:noreply, update(socket, :response, &(&1 <> chunk))}
end

def handle_info({:agent_event, _other}, socket), do: {:noreply, socket}
```

## In agent callbacks

If you only need side effects (logging, telemetry, pubsub) you do not need
to subscribe to the stream. Override `handle_event/2` in the agent module
instead. See the [Agents](agents.md) guide.

Returning `{:stop, reason, state}` from that callback cancels the current
turn, like `Condukt.abort/1`. The session stays alive, releases any compaction
wait, and ignores late events and results from that turn, including while a
replacement turn runs. Clearing history also cancels the current turn.

Once the session processes cancellation, the original `run` caller receives
`{:error, :aborted}`. A stream receives that error and closes immediately,
without waiting for inference or admitted tools to finish. For streaming turns,
the notifier gets the cancellation error and `:done` before a replacement can start. Late
worker completion cannot publish another `:done`. A concurrent stream rejected
with `:already_streaming` closes only its own reader, without publishing an
error or completion for the active conversation.

Native loops check ownership before every provider attempt, after inference,
and before admitting each tool. Cancellation also wakes native retry backoff.
Provider requests already admitted may finish, and admitted tools can still
produce side effects; cancellation does not roll those back or kill external
runtime processes. Slow callbacks, notifiers, snapshot stores, and legacy
synchronous compactors can delay the session's handling of cancellation.

## Steering and follow-ups

While a stream is in flight you can:

* `Condukt.steer/2` to inject a message that joins the running turn after the
  current tool round, before the next model request.
* `Condukt.follow_up/2` to queue a message that starts the next turn once the
  current one finishes.

On an idle session either one starts a turn at once. Turns started from queued
input have no caller, so their events go to the notifier and `handle_event/2`.
A `Condukt.run/3` or `Condukt.stream/3` that arrives during such a turn waits
for it and runs next, instead of failing with `:already_streaming`. Aborting
the turn withdraws queued messages and answers waiting callers with
`{:error, :aborted}`; reports from background sub-agents stay queued. Only the
native runtime takes queued input.

Both are useful for interactive UIs where users can interrupt or guide the
agent without aborting it.

## Watching a session

Events reach a subscriber from the moment it subscribes. A viewer that opens a
session mid-turn, or reconnects, would miss the answer streamed so far, the
tools already running, and the input waiting in the queue. Such a viewer starts
from the session's current view instead, then applies only what changes after
it:

```elixir
view = Condukt.watch(session)
render(view)

def handle_info({:condukt_change, _session_id, epoch, seq, change}, socket) do
  case Condukt.Session.View.advance(socket.assigns.view, epoch, seq, change) do
    {:ok, view} -> {:noreply, render(assign(socket, view: view))}
    :stale -> {:noreply, socket}
    :gap -> {:noreply, assign(socket, view: Condukt.watch(session))}
  end
end
```

`Condukt.watch/1` returns a `Condukt.Session.View` and subscribes the caller to
the changes after it in the same call, so nothing is lost or repeated between
the two. Any number of viewers can watch one session, and any of them can call
`Condukt.steer/2` or `Condukt.follow_up/2`; every viewer sees the queued input
and when it is taken. `Condukt.unwatch/1` stops the changes, as does the
watcher's exit.

The view holds:

| Field | Description |
| ----- | ----------- |
| `messages` | The committed history, newest last. |
| `run` | The turn in flight, or `nil`. Its `items` are its input, steering that joined it, the answer and reasoning streamed so far, and each tool call with its arguments, `:running`/`:ok`/`:error` status, result, and a foreground sub-agent's own run under `subagent`. |
| `error` | Why the last finished turn failed, such as `:aborted`, or `nil`. |
| `queue` | Input waiting to start or join a turn, in the order it is taken: waiting callers (`:prompt`), `:steer`, `:follow_up`, and background sub-agent answers (`:report`). |
| `background` | [Background sub-agents](subagents.md) by name, each with its role, session id, the `call_id` of the call that spawned it, `:working` or `:idle` status, and the `run` of its current or last turn: the message it started from, steering that joined it, and its steps. |
| `agent` | The agent module, model name, thinking level, tool names, and runtime. |
| `epoch`, `seq` | Which session process numbered the changes, and the last change the view holds. |

A turn started with `Condukt.run/3` shows in the view too, one step at a time,
even though it publishes no events.

### Changes

A change is an event from the [event vocabulary](#event-vocabulary), or one of
`{:run_started, message}`, `{:input, message}` for steering joining the run,
`{:run_finished, error, messages}`, `{:messages, :append | :replace, messages}`
for history changed by compaction or `Condukt.clear/1`, `{:queue, items}`,
`{:background, name, entry}` when a background sub-agent starts, changes
status, or (with `nil`) is gone, and `{:background_event, name, event}` for
an event from its turn or the `{:run_started, message}` and `{:input, message}`
that started it and joined it. The parent's notifier events are unchanged.
`View.advance/4` folds them in; a client in another language can apply the same
rules, and only the changes travel after the first view.

The session numbers every change with `seq`, counting from 1 in each `epoch`.
`epoch` names the session process, so numbers from a session that restarted are
never mistaken for the old one's. `advance/4` returns `:stale` for a change the
view already holds and `:gap` for one that does not follow it, including one
from another epoch. On a gap, fetch the view again and continue from there.

### Viewers on other nodes

A notifier that implements `c:Condukt.Notifier.publish_change/5` carries the
same numbered changes to other nodes. `Condukt.Notifiers.PubSub` publishes them
as `{:condukt_change, session_id, epoch, seq, change}` on
`Condukt.Notifiers.PubSub.changes_topic/2`, the message `watch/1` sends
locally. Subscribe first, then fetch the view from the node running the
session, so every change after it arrives. `Condukt.Sessions` registers
sessions on their own node, so ask that node, or call the session's pid:

```elixir
Phoenix.PubSub.subscribe(MyApp.PubSub, Condukt.Notifiers.PubSub.changes_topic(session_id))
view = :erpc.call(session_node, Condukt, :view, [Condukt.Sessions.via(session_id)])
```

Changes published between the subscription and the view are `:stale` and are
dropped. A change PubSub fails to deliver shows up as a `:gap` at the next one.
The event topic and its `{:condukt_event, session_id, event}` messages are
unchanged.

### Secrets

The view and its changes pass user input and tool results through the session's
redactors, `Condukt.Secrets` included, the same way as on the way to the model.
Structured tool results keep their shape with each string redacted. The agent
configuration leaves out keys, base URLs, request options, and the system
prompt. Events sent to `Condukt.stream/3` subscribers and `c:Condukt.Notifier.publish/3`
are unchanged.

Tools waiting on something outside the turn do not show in the view yet.
