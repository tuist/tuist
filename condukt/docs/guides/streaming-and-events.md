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

* `Condukt.steer/2` to inject a message that takes effect after the current
  tool call finishes. Remaining queued tool calls in that turn are skipped.
* `Condukt.follow_up/2` to queue a message that the agent will pick up once
  it finishes the current run.

Both are useful for interactive UIs where users can interrupt or guide the
agent without aborting it.
