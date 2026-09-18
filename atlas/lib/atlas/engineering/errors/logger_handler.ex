defmodule Atlas.Engineering.Errors.LoggerHandler do
  @moduledoc """
  Erlang :logger handler that captures error-level and above events
  emitted by the running Hive instance and records them as Sentry
  events against the "Hive" self-project.

  The handler runs in the calling process, converts the log event to a
  Sentry-shaped map in memory, and calls `Atlas.Engineering.Errors.record_event/2`
  directly. There is no HTTP hop, so an ingest failure cannot trigger
  another log event that re-enters the handler.

  The process dictionary key `:hive_errors_recording?` guards against
  re-entry from any indirect logs the recorder itself might emit.
  """

  alias Atlas.Engineering.Errors
  alias Atlas.Engineering.Errors.SelfMonitor
  alias Atlas.Engineering.Errors.SentryEvent
  alias Atlas.Engineering.Projects.Project
  alias Atlas.Repo

  @handler_id :hive_errors_handler

  @doc """
  Attaches the handler at the `:error` level. Safe to call twice: the
  second call is a no-op.
  """
  def attach do
    config = %{
      level: :error,
      filter_default: :log,
      formatter: {:logger_formatter, %{}}
    }

    case :logger.add_handler(@handler_id, __MODULE__, config) do
      :ok -> :ok
      {:error, {:already_exists, _}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Detaches the handler. Used in tests.
  """
  def detach do
    case :logger.remove_handler(@handler_id) do
      :ok -> :ok
      {:error, {:not_found, _}} -> :ok
    end
  end

  @doc false
  # Callback invoked by :logger for every log event that passes the
  # level filter.
  def log(%{level: level, meta: meta, msg: msg} = event, _config) do
    if !(recording?() or ignore?(meta)) do
      Process.put(:hive_errors_recording?, true)

      try do
        record(level, msg, meta, event)
      rescue
        _ -> :ok
      after
        Process.delete(:hive_errors_recording?)
      end
    end

    :ok
  end

  defp recording?, do: Process.get(:hive_errors_recording?) == true

  defp ignore?(meta) do
    from_ignored_domain?(meta) or from_transport_only_domain?(meta) or
      from_click_house_infra?(meta) or from_click_house_exception?(meta)
  end

  defp from_ignored_domain?(%{domain: domain}) when is_list(domain) do
    Enum.any?(domain, &(&1 in [:hive_errors]))
  end

  defp from_ignored_domain?(_), do: false

  # `:cowboy` / `:bandit` domains are noisy at the HTTP-transport layer —
  # malformed requests from scanners, TLS handshake failures, and so on —
  # but they are also the channel through which a Plug/controller crash
  # bubbles up. Skip them only when the log carries no exception (no
  # `crash_reason`), so real handler crashes still reach the self-project.
  defp from_transport_only_domain?(%{domain: domain} = meta) when is_list(domain) do
    Enum.any?(domain, &(&1 in [:cowboy, :bandit])) and not Map.has_key?(meta, :crash_reason)
  end

  defp from_transport_only_domain?(_), do: false

  # Any log emitted from a Ch.Connection process (the CH driver logs
  # "failed to connect" on every pool worker's failed attempt), the
  # ClickHouse Ecto adapter, or Hive's own ingest buffer. Recording
  # them requires the very CH pool that is currently unhealthy, which
  # amplifies the outage into a log storm without adding a single new
  # data point beyond what the operator already sees in the pod log.
  defp from_click_house_infra?(%{mfa: {mod, _fun, _arity}}) do
    name = Atom.to_string(mod)

    String.starts_with?(name, "Elixir.Ch.") or
      String.starts_with?(name, "Elixir.Ecto.Adapters.ClickHouse") or
      String.starts_with?(name, "Elixir.Atlas.Ingestion.")
  end

  defp from_click_house_infra?(_), do: false

  # Same loop-break for exceptions bubbling up as `:crash_reason`.
  # `Ch.Error` is a CH server error — always. `DBConnection.ConnectionError`
  # is only skipped when the message identifies the ingest repo; a
  # Postgres pool error is a distinct problem and should be recorded.
  defp from_click_house_exception?(%{crash_reason: {reason, _stack}}), do: click_house_exception?(reason)

  defp from_click_house_exception?(_), do: false

  defp click_house_exception?(%{__struct__: Ch.Error}), do: true

  defp click_house_exception?(%{__struct__: DBConnection.ConnectionError, message: msg}) when is_binary(msg),
    do: String.contains?(msg, "Atlas.IngestRepo")

  defp click_house_exception?(_), do: false

  defp record(level, msg, meta, event) do
    with %Project{} = project <- self_project() do
      payload = build_payload(level, msg, meta, event)
      sentry_event = SentryEvent.parse(payload)
      Errors.record_event(project, sentry_event)
    end
  end

  defp self_project do
    case SelfMonitor.self_project_id() do
      nil -> nil
      id -> Repo.get(Project, id)
    end
  end

  defp build_payload(level, msg, meta, event) do
    message = format_msg(msg)
    timestamp = timestamp_iso(meta[:time] || event[:time])

    base = %{
      "event_id" => generate_event_id(),
      "timestamp" => timestamp,
      "platform" => "elixir",
      "level" => normalize_level(level),
      "logger" => logger_name(meta),
      "server_name" => to_string(:net_adm.localhost()),
      "environment" => to_string(Application.get_env(:hive, :env, "production")),
      "release" => to_string(Application.spec(:hive, :vsn)),
      "message" => %{"formatted" => message},
      "sdk" => %{"name" => "hive.self", "version" => "1.0.0"},
      "tags" => tags_from_meta(meta)
    }

    base
    |> maybe_put_exception(meta)
    |> maybe_put_report_exception(msg)
    |> maybe_put_request(meta)
  end

  # Some libraries (Oban telemetry, Broadway, GenServer terminate reports)
  # log a bare Erlang report as `{:report, map}` with no `crash_reason`
  # metadata. Without a synthesized exception the message dump becomes
  # the issue title, which produces a wall of `%{state: :discard, ...}`
  # instead of something like `Oban.DiscardError: Atlas.Domains.EvolutionWorker`.
  # Detect the common shapes here and mint a proper exception.
  defp maybe_put_report_exception(payload, msg) do
    if Map.has_key?(payload, "exception") do
      payload
    else
      case msg do
        {:report, %{event: "background_job_failed"} = report} ->
          put_oban_exception(payload, report)

        {:report, %{event: "background_job_" <> _rest} = report} ->
          put_oban_exception(payload, report)

        _ ->
          payload
      end
    end
  end

  defp put_oban_exception(payload, report) do
    state = Map.get(report, :state, :error)
    worker = to_string(Map.get(report, :worker, "Oban.Worker"))
    error_type = to_string(Map.get(report, :error_type, ""))
    error_message = to_string(Map.get(report, :error_message, ""))
    kind = to_string(Map.get(report, :kind, Map.get(report, :error_kind, "")))

    type = "Oban.#{Macro.camelize(to_string(state))}Error"

    detail =
      present_or_nil(error_message) ||
        present_or_nil(error_type) ||
        present_or_nil(kind)

    value =
      [worker, detail]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(": ")

    Map.put(payload, "exception", %{
      "values" => [
        %{
          "type" => type,
          "value" => value,
          "mechanism" => %{"type" => "oban", "handled" => false}
        }
      ]
    })
  end

  defp present_or_nil(""), do: nil
  defp present_or_nil(nil), do: nil
  defp present_or_nil(v), do: v

  defp format_msg({:string, msg}), do: IO.iodata_to_binary(msg)

  defp format_msg({:report, report}) when is_map(report), do: inspect(report, limit: :infinity)

  defp format_msg({format, args}) when is_list(format) do
    format
    |> :io_lib.format(args)
    |> IO.iodata_to_binary()
  end

  defp format_msg(other), do: inspect(other)

  defp normalize_level(:emergency), do: "fatal"
  defp normalize_level(:alert), do: "fatal"
  defp normalize_level(:critical), do: "fatal"
  defp normalize_level(:error), do: "error"
  defp normalize_level(:warning), do: "warning"
  defp normalize_level(:notice), do: "info"
  defp normalize_level(:info), do: "info"
  defp normalize_level(:debug), do: "debug"
  defp normalize_level(_), do: "error"

  defp logger_name(meta) do
    case meta do
      %{mfa: {mod, fun, arity}} -> "#{inspect(mod)}.#{fun}/#{arity}"
      %{module: mod} -> to_string(mod)
      _ -> "elixir"
    end
  end

  defp tags_from_meta(meta) do
    tags = %{}

    tags =
      case meta do
        %{file: file, line: line} when is_binary(file) or is_list(file) ->
          Map.put(tags, "code.source", "#{to_string(file)}:#{line}")

        _ ->
          tags
      end

    case meta do
      %{request_id: id} when is_binary(id) -> Map.put(tags, "request_id", id)
      _ -> tags
    end
  end

  defp maybe_put_exception(payload, %{crash_reason: {reason, stacktrace}} = meta) when is_list(stacktrace) do
    {type, value} = format_reason(reason, meta)

    Map.put(payload, "exception", %{
      "values" => [
        %{
          "type" => type,
          "value" => value,
          "stacktrace" => %{"frames" => stacktrace_frames(stacktrace)}
        }
      ]
    })
  end

  defp maybe_put_exception(payload, _meta), do: payload

  defp maybe_put_request(payload, %{conn: %Plug.Conn{} = conn}) do
    Map.put(payload, "request", %{
      "url" => request_url(conn),
      "method" => conn.method,
      "headers" => safe_headers(conn.req_headers),
      "query_string" => conn.query_string
    })
  end

  defp maybe_put_request(payload, _), do: payload

  defp request_url(conn) do
    "#{conn.scheme}://#{conn.host}#{conn.request_path}"
  end

  defp safe_headers(headers) do
    Map.new(headers, fn {k, v} ->
      case String.downcase(k) do
        "authorization" -> {k, "[filtered]"}
        "cookie" -> {k, "[filtered]"}
        "x-sentry-auth" -> {k, "[filtered]"}
        _ -> {k, v}
      end
    end)
  end

  defp format_reason(reason, _meta) when is_exception(reason) do
    {inspect(reason.__struct__), Exception.message(reason)}
  end

  defp format_reason({:nocatch, value}, _meta), do: {"throw", inspect(value)}

  # Oban wraps failed jobs as `Oban.PerformError` on the crash_reason, but
  # workers that return `{:error, reason}` or `{:discard, reason}` show up
  # as a job state map. Prefer the worker name + reason for the title,
  # which is closer to what Sentry's Oban integration produces than a raw
  # map dump.
  defp format_reason(%{state: state} = job, meta) when state in [:discard, :failure] do
    worker = worker_name(job, meta)
    value = format_state_reason(job, meta, state)
    {"Oban.#{Macro.camelize(to_string(state))}Error", "#{worker}: #{value}"}
  end

  defp format_reason({{:nocatch, value}, _stacktrace}, meta), do: format_reason({:nocatch, value}, meta)

  defp format_reason({reason, _}, meta) when is_exception(reason), do: format_reason(reason, meta)

  defp format_reason(reason, _meta) do
    {"process_exit", truncate(inspect(reason), 500)}
  end

  defp worker_name(job, _meta) do
    case job do
      %{worker: worker} when is_binary(worker) -> worker
      %{worker: worker} when is_atom(worker) -> inspect(worker)
      _ -> "Oban.Worker"
    end
  end

  defp format_state_reason(job, _meta, state) do
    reason =
      case job do
        %{error: error} when not is_nil(error) -> inspect(error)
        %{result: result} when not is_nil(result) -> inspect(result)
        _ -> to_string(state)
      end

    truncate(reason, 200)
  end

  defp truncate(binary, max) when is_binary(binary) and byte_size(binary) > max do
    String.slice(binary, 0, max) <> "..."
  end

  defp truncate(binary, _max), do: binary

  defp stacktrace_frames(frames) do
    frames
    |> Enum.reverse()
    |> Enum.map(&frame/1)
  end

  defp frame({mod, fun, arity_or_args, location}) do
    arity = if is_list(arity_or_args), do: length(arity_or_args), else: arity_or_args
    file = Keyword.get(location, :file)
    line = Keyword.get(location, :line)

    %{
      "module" => inspect(mod),
      "function" => "#{fun}/#{arity}",
      "filename" => file && to_string(file),
      "lineno" => line,
      "in_app" => in_app?(mod)
    }
  end

  defp frame(_), do: %{}

  defp in_app?(module) do
    module
    |> inspect()
    |> String.starts_with?(["Hive", "HiveWeb"])
  end

  defp generate_event_id do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
  end

  defp timestamp_iso(time) when is_integer(time) do
    time
    |> DateTime.from_unix!(:microsecond)
    |> DateTime.to_iso8601()
  end

  defp timestamp_iso(_), do: DateTime.utc_now() |> DateTime.to_iso8601()
end
