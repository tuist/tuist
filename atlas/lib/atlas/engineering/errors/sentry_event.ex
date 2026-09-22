defmodule Atlas.Engineering.Errors.SentryEvent do
  @moduledoc """
  Parsed representation of a Sentry event item payload. The parser
  accepts the raw decoded JSON map produced by any Sentry-compatible
  SDK, normalizes what Hive needs into typed fields, and keeps the
  full payload verbatim under `:payload` for storage.

  Field names follow the Sentry event schema documented at
  <https://develop.sentry.dev/sdk/data-model/event-payloads/>.
  """

  defstruct [
    :event_id,
    :timestamp,
    :platform,
    :level,
    :environment,
    :release,
    :dist,
    :server_name,
    :transaction,
    :logger,
    :tracing_name,
    :exception_type,
    :exception_value,
    :top_frame,
    :message,
    :user,
    :request,
    :sdk_name,
    :sdk_version,
    :fingerprint_override,
    :tags,
    :payload
  ]

  @levels ~w(fatal error warning info debug)

  @doc """
  Parses a raw decoded event map. Missing fields are tolerated; the
  parser never raises so a malformed SDK cannot bring down ingestion.
  """
  def parse(payload) when is_map(payload) do
    exception_values = exception_values(payload)
    {exception_type, exception_value, exception_frames} = first_exception(exception_values)
    top_frame = top_in_app_frame(exception_frames)

    %__MODULE__{
      event_id: normalize_event_id(payload["event_id"]),
      timestamp: parse_timestamp(payload["timestamp"]),
      platform: string(payload["platform"], "other"),
      level: normalize_level(payload["level"]),
      environment: string(payload["environment"], "production"),
      release: string(payload["release"]),
      dist: string(payload["dist"]),
      server_name: string(payload["server_name"]),
      transaction: string(payload["transaction"]),
      logger: string(payload["logger"]),
      tracing_name: parse_tracing_name(payload),
      exception_type: exception_type,
      exception_value: exception_value,
      top_frame: top_frame,
      message: parse_message(payload),
      user: parse_user(payload["user"]),
      request: parse_request(payload["request"]),
      sdk_name: sdk_field(payload["sdk"], "name"),
      sdk_version: sdk_field(payload["sdk"], "version"),
      fingerprint_override: fingerprint_override(payload["fingerprint"]),
      tags: parse_tags(payload["tags"]),
      payload: payload
    }
  end

  @doc """
  A short, human-readable title for the issue. Falls back through
  message, formatted logentry, tracing event name, logger, and
  event_id.
  """
  def title(%__MODULE__{exception_type: type, exception_value: value}) when is_binary(type) and byte_size(type) > 0 do
    case value do
      value when is_binary(value) and byte_size(value) > 0 -> "#{type}: #{value}"
      _ -> type
    end
  end

  def title(%__MODULE__{message: message}) when is_binary(message) and byte_size(message) > 0, do: message

  def title(%__MODULE__{tracing_name: name}) when is_binary(name) and byte_size(name) > 0, do: name

  def title(%__MODULE__{logger: logger}) when is_binary(logger) and byte_size(logger) > 0, do: logger

  def title(%__MODULE__{event_id: event_id}), do: "Event #{event_id}"

  @doc """
  A short "where" descriptor for the issue, e.g. `MyModule.function/2
  at lib/my_module.ex:42`.
  """
  def culprit(%__MODULE__{top_frame: nil, transaction: transaction}), do: transaction

  def culprit(%__MODULE__{top_frame: frame, transaction: transaction}) do
    parts =
      [frame["function"] || frame["module"], location_part(frame)]
      |> Enum.filter(&present_string?/1)

    case parts do
      [] -> transaction
      _ -> Enum.join(parts, " at ")
    end
  end

  defp location_part(frame) do
    filename = frame["filename"] || frame["abs_path"]
    lineno = frame["lineno"]

    case {filename, lineno} do
      {name, line} when is_binary(name) and not is_nil(line) -> "#{name}:#{line}"
      {name, _} when is_binary(name) -> name
      _ -> nil
    end
  end

  defp present_string?(value) when is_binary(value) and byte_size(value) > 0, do: true
  defp present_string?(_), do: false

  defp exception_values(payload) do
    case payload["exception"] do
      %{"values" => values} when is_list(values) -> values
      values when is_list(values) -> values
      _ -> []
    end
  end

  defp first_exception([]), do: {nil, nil, []}

  defp first_exception([first | _]) when is_map(first) do
    frames =
      case first["stacktrace"] do
        %{"frames" => frames} when is_list(frames) -> frames
        _ -> []
      end

    {string(first["type"]), string(first["value"]), frames}
  end

  defp first_exception(_), do: {nil, nil, []}

  defp top_in_app_frame([]), do: nil

  defp top_in_app_frame(frames) when is_list(frames) do
    in_app = Enum.reverse(Enum.filter(frames, &match?(%{"in_app" => true}, &1)))

    case in_app do
      [frame | _] -> frame
      [] -> List.last(frames)
    end
  end

  defp parse_message(payload) do
    cond do
      is_binary(payload["message"]) and byte_size(payload["message"]) > 0 ->
        payload["message"]

      is_map(payload["message"]) ->
        payload["message"]["formatted"] || payload["message"]["message"]

      is_map(payload["logentry"]) ->
        payload["logentry"]["formatted"] || payload["logentry"]["message"]

      true ->
        nil
    end
  end

  # The Rust SDK's `tracing` integration emits events with no
  # exception, no frames, and an empty message; the event's name is
  # carried in this context instead.
  defp parse_tracing_name(payload) do
    case payload["contexts"] do
      %{"Rust Tracing Fields" => %{"name" => name}} -> string(name)
      _ -> nil
    end
  end

  defp parse_user(user) when is_map(user) do
    %{
      id: string(user["id"]),
      email: string(user["email"]),
      ip_address: string(user["ip_address"]),
      username: string(user["username"])
    }
  end

  defp parse_user(_), do: %{id: nil, email: nil, ip_address: nil, username: nil}

  defp parse_request(request) when is_map(request) do
    %{
      url: string(request["url"]),
      method: string(request["method"])
    }
  end

  defp parse_request(_), do: %{url: nil, method: nil}

  defp fingerprint_override(fingerprint) when is_list(fingerprint) do
    case Enum.map(fingerprint, &to_string/1) do
      [] -> nil
      list -> list
    end
  end

  defp fingerprint_override(_), do: nil

  defp parse_tags(tags) when is_map(tags) do
    tags
    |> Enum.flat_map(fn
      {k, v} when is_binary(v) -> [{to_string(k), v}]
      {k, v} when is_number(v) or is_boolean(v) -> [{to_string(k), to_string(v)}]
      _ -> []
    end)
    |> Map.new()
  end

  defp parse_tags(tags) when is_list(tags) do
    tags
    |> Enum.flat_map(fn
      [k, v] when is_binary(v) -> [{to_string(k), v}]
      [k, v] -> [{to_string(k), to_string(v)}]
      _ -> []
    end)
    |> Map.new()
  end

  defp parse_tags(_), do: %{}

  defp sdk_field(sdk, key) when is_map(sdk), do: string(sdk[key])
  defp sdk_field(_, _), do: nil

  defp normalize_level(level) when is_binary(level) do
    downcased = String.downcase(level)
    if downcased in @levels, do: downcased, else: "error"
  end

  defp normalize_level(_), do: "error"

  defp normalize_event_id(id) when is_binary(id) do
    id
    |> String.replace("-", "")
    |> String.downcase()
    |> String.pad_leading(32, "0")
    |> String.slice(0, 32)
  end

  defp normalize_event_id(_) do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
  end

  defp parse_timestamp(nil), do: DateTime.utc_now()

  defp parse_timestamp(value) when is_number(value) do
    micros = round(value * 1_000_000)
    DateTime.from_unix!(micros, :microsecond)
  end

  defp parse_timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> dt
      {:error, :missing_offset} -> parse_naive_timestamp(value)
      _ -> DateTime.utc_now()
    end
  end

  defp parse_timestamp(_), do: DateTime.utc_now()

  defp parse_naive_timestamp(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, naive} -> DateTime.from_naive!(naive, "Etc/UTC")
      _ -> DateTime.utc_now()
    end
  end

  defp string(nil, default), do: default
  defp string("", default), do: default
  defp string(value, _default) when is_binary(value), do: value
  defp string(value, default) when is_atom(value), do: to_string(value) || default
  defp string(_, default), do: default

  defp string(value), do: string(value, nil)
end
