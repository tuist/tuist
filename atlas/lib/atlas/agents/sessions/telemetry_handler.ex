defmodule Atlas.Agents.Sessions.TelemetryHandler do
  @moduledoc """
  Persists Condukt telemetry events as `agent_session_events` rows so that
  every agentic run has a complete audit trail in the database.

  Attached once at application start via `attach/0`. Each handler invocation
  is synchronous so events arrive in emission order, but we silently drop
  events whose `:session_id` we have not yet inserted (for example, runs
  invoked through Condukt directly rather than `Atlas.Agents.Sessions`).
  """

  alias Atlas.Agents.Sessions.Event
  alias Atlas.Repo

  require Logger

  @handler_id "atlas-agents-sessions"

  @events [
    [:condukt, :run, :start],
    [:condukt, :run, :stop],
    [:condukt, :run, :exception],
    [:condukt, :llm_turn, :start],
    [:condukt, :llm_turn, :stop],
    [:condukt, :llm_turn, :exception],
    [:condukt, :agent, :start],
    [:condukt, :agent, :stop],
    [:condukt, :agent, :exception],
    [:condukt, :tool_call, :start],
    [:condukt, :tool_call, :stop],
    [:condukt, :tool_call, :exception],
    [:condukt, :subagent, :start],
    [:condukt, :subagent, :stop],
    [:condukt, :operation, :start],
    [:condukt, :operation, :stop],
    [:condukt, :operation, :exception],
    [:condukt, :secrets, :resolve],
    [:condukt, :secrets, :access],
    [:condukt, :compact, :stop]
  ]

  def attach do
    :telemetry.attach_many(@handler_id, @events, &__MODULE__.handle_event/4, nil)
  end

  def detach do
    :telemetry.detach(@handler_id)
  end

  def handle_event([:condukt | rest], measurements, metadata, _config) do
    {phase, type_atoms} = List.pop_at(rest, -1)
    type = type_atoms |> Enum.map_join(".", &Atom.to_string/1)

    case Map.get(metadata, :session_id) do
      nil ->
        :ok

      session_id when is_binary(session_id) ->
        insert_event(session_id, type, Atom.to_string(phase), measurements, metadata)
    end
  end

  # `:telemetry` detaches a handler permanently the first time it crashes, which
  # would silently turn off the whole agent audit trail for the rest of the node
  # over one unavailable connection or one malformed payload. Recording an event
  # is never worth that, so every failure is logged and swallowed here. It
  # catches exits and throws as well as raises because `:telemetry` matches every
  # exception class, so an insert that exits detaches the handler just as a raise
  # would. The stacktrace goes into the log because this warning is the only
  # trace anyone gets of a dropped event.
  defp insert_event(session_id, type, phase, measurements, metadata) do
    do_insert_event(session_id, type, phase, measurements, metadata)
  rescue
    exception ->
      Logger.warning("agent session event insert raised: " <> Exception.format(:error, exception, __STACKTRACE__))

      :ok
  catch
    kind, reason ->
      Logger.warning("agent session event insert crashed: " <> Exception.format(kind, reason, __STACKTRACE__))

      :ok
  end

  defp do_insert_event(session_id, type, phase, measurements, metadata) do
    attrs = %{
      agent_session_id: session_id,
      type: type,
      name: extract_name(type, metadata),
      phase: phase,
      duration_ms: duration_ms(measurements),
      metadata: sanitize(metadata),
      occurred_at: DateTime.utc_now()
    }

    attrs
    |> Event.changeset()
    |> Repo.insert()
    |> case do
      {:ok, _event} ->
        :ok

      {:error, %Ecto.Changeset{errors: [{:agent_session_id, _} | _]}} ->
        # Session row not present yet; this happens when a run starts outside
        # `Atlas.Agents.Sessions.run/3`. Drop silently rather than crashing
        # the agent process.
        :ok

      {:error, changeset} ->
        Logger.warning("agent session event insert failed: #{inspect(changeset.errors)}")
        :ok
    end
  end

  defp extract_name("tool_call", %{tool: tool}), do: tool
  defp extract_name("subagent", %{role: role}) when is_atom(role), do: Atom.to_string(role)
  defp extract_name("operation", %{operation: name}) when is_atom(name), do: Atom.to_string(name)
  defp extract_name("llm_turn", %{turn: turn}) when is_integer(turn), do: "turn #{turn}"
  defp extract_name(_type, _metadata), do: nil

  defp duration_ms(%{duration: native}) when is_integer(native) do
    System.convert_time_unit(native, :native, :millisecond)
  end

  defp duration_ms(_), do: nil

  # Telemetry metadata may contain non-JSON-friendly terms (PIDs, refs,
  # module atoms). Convert them to strings so the jsonb column accepts the
  # row, and drop the noisy fields callers don't need on the audit page.
  defp sanitize(metadata) do
    metadata
    |> Map.drop([:session_id, :stacktrace])
    |> Map.new(fn {key, value} -> {Atom.to_string(key), encode_value(value)} end)
  end

  defp encode_value(value) when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value), do: value
  defp encode_value(value) when is_atom(value), do: Atom.to_string(value)
  defp encode_value(value) when is_list(value), do: Enum.map(value, &encode_value/1)

  defp encode_value(%Condukt.Message{} = msg) do
    %{
      "role" => encode_value(msg.role),
      "content" => encode_message_content(msg.content),
      "tool_call_id" => msg.tool_call_id
    }
  end

  defp encode_value(value) when is_map(value) and not is_struct(value) do
    Map.new(value, fn {key, inner} -> {to_string(key), encode_value(inner)} end)
  end

  defp encode_value({:error, reason}), do: %{"error" => encode_value(reason)}
  defp encode_value(value), do: inspect(value)

  defp encode_message_content(content) when is_binary(content), do: content
  defp encode_message_content(content) when is_list(content), do: Enum.map(content, &encode_content_part/1)
  defp encode_message_content(other), do: encode_value(other)

  defp encode_content_part({:text, text}) when is_binary(text), do: %{"type" => "text", "text" => text}
  defp encode_content_part(value), do: encode_value(value)
end
