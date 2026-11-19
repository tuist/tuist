defmodule Condukt.Session.View do
  @moduledoc """
  What a viewer of a session sees: its current state, kept by folding changes.

  A viewer that attaches to a session mid-turn, or reconnects, starts from the
  session's view and then applies only the changes after it. The view holds:

    * `messages` - the committed history, newest last
    * `run` - the turn in flight, or `nil` when the session is idle. Its
      `items` are the turn's steps in order, starting with its input:
      `%{type: :user, message: message}`,
      `%{type: :assistant, text: text, thinking: thinking}`, or
      `%{type: :tool, id: id, name: name, args: args, status: status, result: result, output: output, subagent: run}`.
      A tool's `status` is `:running` until its result arrives, then `:ok` or
      `:error`. `output` is what the call streamed while it ran, as
      `{:tool_output, tool_call_id, chunk}` events, up to its last 64 KiB. `subagent` holds a foreground sub-agent's own run, folded from
      the `{:subagent, tool_call_id, event}` events of that call. Its `error`
      holds an `{:error, reason}` the turn reported.
    * `error` - why the last finished turn failed, or `nil`
    * `queue` - input waiting to start or join a turn, in the order the session
      takes it, each `%{kind: kind, message: message}` with `kind` one of
      `:prompt` (a caller's `run` or `stream` waiting), `:steer`, `:follow_up`,
      `:input` (submitted by id with `Condukt.Sessions.submit/3`), or `:report`
      (a background sub-agent's answer)
    * `background` - background sub-agents by name, each
      `%{name: name, role: role, session_id: id, call_id: id, status: status, run: run}`.
      `call_id` is the tool call that spawned it, `status` is `:working` or
      `:idle`, and `run` holds its current or last turn, the same shape as the
      session's own run: the message the turn started from, steering that
      joined it, and its steps. It is `nil` before the first turn starts.
    * `agent` - the agent module, model name, thinking level, tool names, and
      runtime module

  Nothing in the view carries a secret. User input and tool results, in the
  history, the run, the queue, and the changes, pass through the session's
  redactors, `Condukt.Secrets` included, as they do on their way to the model.
  The configuration leaves out keys, URLs, options, and the system prompt.

  ## Changes

  The session's view process numbers each change. It is linked to the
  session and lives as long as it does. `epoch` is drawn when the session
  starts, so a restarted session's numbers are not mistaken for the old
  one's, and `seq` counts its changes; the view records the position of the
  last one it holds.
  A change is an event the session published, with tool results redacted, or
  one of:

    * `{:run_started, message}` - a turn started from this input
    * `{:input, message}` - steering joined the running turn
    * `{:run_finished, error, messages}` - the turn ended, adding `messages` to
      the history; `error` is why it failed, or `nil`
    * `{:messages, :append | :replace, messages}` - the history changed outside
      a turn ending, such as by compaction or `Condukt.clear/1`
    * `{:queue, items}` - queued input changed
    * `{:background, name, entry}` - a background sub-agent started or changed
      status, or, with `nil`, is gone
    * `{:background_event, name, event}` - a background sub-agent's turn
      changed: `event` is one of its events, or `{:run_started, message}` and
      `{:input, message}` as above

  `advance/4` applies a numbered change and tells a viewer when it missed one.
  Changes are what a remote viewer needs; the view itself is only sent once.
  """

  alias Condukt.Message
  alias Condukt.Redactor

  defstruct [:session_id, :epoch, :agent, seq: 0, messages: [], run: nil, error: nil, queue: [], background: %{}]

  # How much of a call's streamed output the view keeps: the end, where a
  # running command is.
  @max_output 64 * 1024

  @doc false
  def new(session_id, agent, messages) do
    %__MODULE__{
      session_id: session_id,
      epoch: :crypto.strong_rand_bytes(6) |> :binary.decode_unsigned() |> max(1),
      agent: agent,
      messages: messages
    }
  end

  @doc """
  Applies the change numbered `seq` in `epoch`.

  Returns `{:ok, view}` for the next change, `:stale` for one the view already
  holds, which a viewer drops, and `:gap` when the viewer missed changes or the
  session restarted. On a gap, fetch the view again with
  `Condukt.Session.view/1` and keep applying from there.
  """
  def advance(%__MODULE__{epoch: epoch, seq: current} = view, epoch, seq, change) when seq == current + 1 do
    {:ok, %{fold(view, change) | seq: seq}}
  end

  def advance(%__MODULE__{epoch: epoch, seq: current}, epoch, seq, _change) when seq <= current, do: :stale
  def advance(%__MODULE__{}, _epoch, _seq, _change), do: :gap

  @doc "Whether a turn is in flight."
  def running?(%__MODULE__{run: run}), do: run != nil

  @doc false
  # Queued input as the view shows it, from the turn's queues in the order
  # `Condukt.Session.Turn.next_input/1` takes them.
  def queue(turn) do
    Enum.map(turn.pending, fn {prompt, opts, _recipient} ->
      %{kind: :prompt, message: %Message{role: :user, content: prompt, images: opts[:images] || []}}
    end) ++
      Enum.map(turn.steering_messages, &%{kind: :steer, message: &1}) ++
      Enum.map(turn.follow_up_messages, &%{kind: :follow_up, message: &1}) ++
      Enum.map(turn.inputs, fn {_input, message} -> %{kind: :input, message: message} end) ++
      Enum.map(turn.reports, fn {_tag, message} -> %{kind: :report, message: message} end)
  end

  @doc false
  # Redacts what a redactor would catch on its way to the model: user input
  # and tool results, in messages, events, and changes, sub-agents' included.
  # The view process redacts each change once, as it arrives, so the cost
  # follows the change, not the length of the history. Unlike
  # `Condukt.Redactor.redact_messages/2`, structured results keep their shape,
  # so a viewer still tells `{:error, reason}` apart. Model output and tool
  # arguments pass through, as they do in the events themselves.
  def redact(value, []), do: value
  def redact(value, nil), do: value

  def redact(messages, spec) when is_list(messages), do: Enum.map(messages, &redact(&1, spec))

  def redact(%Message{role: role} = message, spec) when role in [:user, :tool_result],
    do: %{message | content: redact_value(message.content, spec)}

  def redact(%Message{} = message, _spec), do: message
  def redact(%{message: message} = item, spec), do: %{item | message: redact(message, spec)}
  def redact({kind, %Message{} = message}, spec) when kind in [:run_started, :input], do: {kind, redact(message, spec)}

  def redact({:run_finished, error, messages}, spec), do: {:run_finished, error, redact(messages, spec)}
  def redact({:messages, mode, messages}, spec), do: {:messages, mode, redact(messages, spec)}
  def redact({:queue, items}, spec), do: {:queue, redact(items, spec)}
  def redact({:background_event, name, event}, spec), do: {:background_event, name, redact(event, spec)}

  def redact({:tool_result, id, result}, spec), do: {:tool_result, id, redact_value(result, spec)}
  def redact({:tool_output, id, chunk}, spec), do: {:tool_output, id, redact_value(chunk, spec)}
  def redact({:subagent, id, event}, spec), do: {:subagent, id, redact(event, spec)}
  def redact(event, _spec), do: event

  defp redact_value(text, spec) when is_binary(text), do: Redactor.apply(spec, text)
  defp redact_value(list, spec) when is_list(list), do: Enum.map(list, &redact_value(&1, spec))

  defp redact_value(tuple, spec) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> redact_value(spec) |> List.to_tuple()

  defp redact_value(map, spec) when is_map(map) and not is_struct(map),
    do: Map.new(map, fn {key, value} -> {key, redact_value(value, spec)} end)

  defp redact_value(value, _spec), do: value

  defp fold(view, {:run_started, message}),
    do: %{view | run: %{items: [%{type: :user, message: message}], error: nil}, error: nil}

  defp fold(view, {:run_finished, error, messages}) do
    %{view | messages: view.messages ++ messages, run: nil, error: error || (view.run && view.run.error)}
  end

  defp fold(view, {:messages, :append, messages}), do: %{view | messages: view.messages ++ messages}
  defp fold(view, {:messages, :replace, messages}), do: %{view | messages: messages}
  defp fold(view, {:queue, items}), do: %{view | queue: items}
  defp fold(view, {:background, name, nil}), do: %{view | background: Map.delete(view.background, name)}

  defp fold(view, {:background, name, entry}) do
    run = get_in(view.background, [name, :run])
    %{view | background: Map.put(view.background, name, Map.put(entry, :run, run))}
  end

  defp fold(view, {:background_event, name, event}) do
    case view.background do
      %{^name => entry} -> put_in(view.background[name], %{entry | run: fold_background(entry.run, event)})
      _missing -> view
    end
  end

  defp fold(%{run: nil} = view, _event), do: view
  defp fold(view, event), do: %{view | run: fold_run(view.run, event)}

  # Each of a background sub-agent's turns starts its run over, from its input.
  defp fold_background(_run, {:run_started, message}), do: %{items: [%{type: :user, message: message}], error: nil}
  defp fold_background(nil, event), do: fold_run(%{items: [], error: nil}, event)
  defp fold_background(run, event), do: fold_run(run, event)

  defp fold_run(run, {:input, message}), do: push(run, %{type: :user, message: message})
  defp fold_run(run, {:text, chunk}), do: update_assistant(run, :text, chunk)
  defp fold_run(run, {:thinking, chunk}), do: update_assistant(run, :thinking, chunk)

  defp fold_run(run, {:tool_call, name, id, args}) do
    push(run, %{type: :tool, id: id, name: name, args: args, status: :running, result: nil, output: "", subagent: nil})
  end

  defp fold_run(run, {:tool_output, id, chunk}) do
    update_tool(run, id, &%{&1 | output: keep_end(&1.output <> chunk)})
  end

  defp fold_run(run, {:tool_result, id, result}) do
    status = if match?({:error, _}, result), do: :error, else: :ok
    update_tool(run, id, &%{&1 | status: status, result: result})
  end

  # A sub-agent's events build its own run under the call that started it.
  defp fold_run(run, {:subagent, id, event}) do
    update_tool(run, id, fn tool ->
      %{tool | subagent: fold_run(tool.subagent || %{items: [], error: nil}, event)}
    end)
  end

  defp fold_run(run, {:error, reason}), do: %{run | error: reason}
  defp fold_run(run, _event), do: run

  defp push(run, item), do: %{run | items: run.items ++ [item]}

  # Keeps the last `@max_output` bytes, from a line start where there is one
  # so a cut does not split a character.
  defp keep_end(output) when byte_size(output) <= @max_output, do: output

  defp keep_end(output) do
    kept = binary_part(output, byte_size(output) - @max_output, @max_output)

    case :binary.match(kept, "\n") do
      {position, 1} -> binary_part(kept, position + 1, byte_size(kept) - position - 1)
      :nomatch -> kept
    end
  end

  defp update_assistant(run, field, chunk) do
    case List.last(run.items) do
      %{:type => :assistant, ^field => current} = item ->
        %{run | items: List.replace_at(run.items, -1, %{item | field => current <> chunk})}

      _other ->
        push(run, Map.put(%{type: :assistant, text: "", thinking: ""}, field, chunk))
    end
  end

  defp update_tool(run, id, fun) do
    %{run | items: Enum.map(run.items, &if(match?(%{type: :tool, id: ^id}, &1), do: fun.(&1), else: &1))}
  end
end
