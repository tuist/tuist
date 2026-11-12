defmodule Condukt.TraceContext do
  @moduledoc """
  A lightweight carrier for [World Wide Web Consortium Trace Context](https://www.w3.org/TR/trace-context/)
  headers.

  Condukt does not start traces or export telemetry. Applications can opt in to
  propagation by passing a context through `:trace_context`, or by storing one
  in the calling process with `put_current/1`. Native model calls then receive
  a fresh child `traceparent`, optional `tracestate`, and a `baggage` entry that
  identifies the opaque Condukt session.

      context = Condukt.TraceContext.new()

      Condukt.run(MyApp.Agent, "Summarize this report.",
        trace_context: context
      )

  This module only carries identifiers. It has no dependency on, or runtime
  requirement for, an OpenTelemetry implementation.
  """

  @compile {:no_warn_undefined, {:otel_propagator_text_map, :inject, 1}}

  @enforce_keys [:trace_id, :span_id]
  defstruct [:trace_id, :span_id, flags: "01", tracestate: nil, baggage: nil]

  @current_key {__MODULE__, :current}

  @doc """
  Creates a trace context suitable for a Condukt run.

  Supplying `:trace_id` and `:span_id` is useful when adapting a context from
  another tracing implementation. `:tracestate` and `:baggage` are forwarded
  unchanged, apart from Condukt replacing its own session baggage entry.
  """
  def new(opts \\ []) do
    trace_id = Keyword.get(opts, :trace_id, random_hex(16))
    span_id = Keyword.get(opts, :span_id, random_hex(8))
    flags = Keyword.get(opts, :flags, "01")

    if valid_trace_id?(trace_id) and valid_span_id?(span_id) and valid_flags?(flags) do
      %__MODULE__{
        trace_id: String.downcase(trace_id),
        span_id: String.downcase(span_id),
        flags: String.downcase(flags),
        tracestate: present_string(Keyword.get(opts, :tracestate)),
        baggage: present_string(Keyword.get(opts, :baggage))
      }
    else
      raise ArgumentError,
            "trace IDs and span IDs must be non-zero hexadecimal strings; trace flags must be hexadecimal"
    end
  end

  @doc """
  Extracts a trace context from World Wide Web Consortium propagation headers.
  """
  def from_headers(headers) when is_map(headers), do: from_headers(Map.to_list(headers))

  def from_headers(headers) when is_list(headers) do
    case header_value(headers, "traceparent") do
      nil ->
        {:error, :missing_traceparent}

      traceparent ->
        with {:ok, trace_id, span_id, flags} <- parse_traceparent(traceparent) do
          {:ok,
           %__MODULE__{
             trace_id: trace_id,
             span_id: span_id,
             flags: flags,
             tracestate: header_value(headers, "tracestate"),
             baggage: header_value(headers, "baggage")
           }}
        end
    end
  end

  @doc """
  Binds the current OpenTelemetry trace to the calling process.

  This is an optional integration point. It dynamically invokes the
  OpenTelemetry text-map propagator, so using Condukt does not require an
  OpenTelemetry dependency. When the application has no active OpenTelemetry
  trace, it clears any Condukt trace context and returns `nil`.

      Condukt.TraceContext.put_current_from_otel!()
  """
  def put_current_from_otel! do
    headers = current_otel_headers!()

    case from_headers(headers) do
      {:ok, context} ->
        put_current(context)

      {:error, :missing_traceparent} ->
        clear_current()
        nil

      {:error, :invalid_traceparent} ->
        raise ArgumentError, "OpenTelemetry returned an invalid traceparent header"
    end
  end

  @doc """
  Returns a fresh child context for one outbound operation.
  """
  def child(nil), do: nil

  def child(%__MODULE__{} = context) do
    %{context | span_id: random_hex(8)}
  end

  @doc """
  Captures the context selected by request options or the calling process.

  `trace_context: true` starts a new root context when the process has none.
  `trace_context: false` disables propagation for that run. Omitting the option
  uses `current/0`, so applications can bind their own tracing integration once
  around a request handler.
  """
  def capture(opts) when is_list(opts) do
    case Keyword.get(opts, :trace_context, :current) do
      :current ->
        current()

      true ->
        current() || new()

      false ->
        nil

      nil ->
        nil

      %__MODULE__{} = context ->
        context

      _ ->
        raise ArgumentError,
              "trace_context must be true, false, nil, or a Condukt.TraceContext"
    end
  end

  @doc """
  Returns the context associated with the current process, if any.
  """
  def current do
    case Process.get(@current_key) do
      %__MODULE__{} = context -> context
      _ -> nil
    end
  end

  @doc """
  Stores a trace context in the current process and returns it.

  Condukt captures this value at the public run or stream boundary before it
  crosses process boundaries.
  """
  def put_current(%__MODULE__{} = context) do
    Process.put(@current_key, context)
    context
  end

  @doc """
  Removes the current process context.
  """
  def clear_current, do: Process.delete(@current_key)

  @doc false
  def attach(nil) do
    clear_current()
    :ok
  end

  def attach(%__MODULE__{} = context) do
    Process.put(@current_key, context)
    :ok
  end

  @doc false
  def headers(nil, _session_id), do: []

  def headers(%__MODULE__{} = context, session_id) when is_binary(session_id) do
    [
      {"traceparent", traceparent(context)},
      {"baggage", baggage(context.baggage, session_id)}
    ]
    |> maybe_put_tracestate(context.tracestate)
  end

  defp maybe_put_tracestate(headers, nil), do: headers
  defp maybe_put_tracestate(headers, ""), do: headers
  defp maybe_put_tracestate(headers, tracestate), do: [{"tracestate", tracestate} | headers]

  defp traceparent(%__MODULE__{} = context) do
    "00-#{context.trace_id}-#{context.span_id}-#{context.flags}"
  end

  defp baggage(existing, session_id) do
    existing
    |> without_baggage_key("condukt.session.id")
    |> append_baggage("condukt.session.id=#{URI.encode(session_id, &URI.char_unreserved?/1)}")
  end

  defp append_baggage(nil, entry), do: entry
  defp append_baggage("", entry), do: entry
  defp append_baggage(existing, entry), do: existing <> "," <> entry

  defp without_baggage_key(nil, _key), do: nil

  defp without_baggage_key(baggage, key) do
    baggage
    |> String.split(",", trim: true)
    |> Enum.reject(&(baggage_key(&1) == key))
    |> Enum.join(",")
    |> present_string()
  end

  defp baggage_key(item) do
    item
    |> String.split(";", parts: 2)
    |> hd()
    |> String.split("=", parts: 2)
    |> hd()
    |> String.trim()
    |> String.downcase()
  end

  defp parse_traceparent(traceparent) when is_binary(traceparent) do
    case String.split(traceparent, "-") do
      [version, trace_id, span_id, flags] ->
        parse_traceparent_fields(version, trace_id, span_id, flags)

      [version, trace_id, span_id, flags | _extra] when version != "00" ->
        parse_traceparent_fields(version, trace_id, span_id, flags)

      _ ->
        {:error, :invalid_traceparent}
    end
  end

  defp parse_traceparent(_), do: {:error, :invalid_traceparent}

  defp header_value(headers, wanted) do
    Enum.find_value(headers, fn
      {name, value} when is_binary(value) and is_binary(name) ->
        if String.downcase(name) == wanted, do: value

      {name, value} when is_binary(value) ->
        if String.downcase(to_string(name)) == wanted, do: value

      _ ->
        nil
    end)
  end

  defp valid_trace_id?(value), do: valid_hex?(value, 32)
  defp valid_span_id?(value), do: valid_hex?(value, 16)
  defp valid_flags?(value), do: valid_hex_value?(value, 2)
  defp valid_version?(value), do: valid_hex_value?(value, 2) and String.downcase(value) != "ff"

  defp valid_hex?(value, length), do: valid_hex_value?(value, length) and value != String.duplicate("0", length)

  defp valid_hex_value?(value, length) when is_binary(value) and byte_size(value) == length,
    do: String.match?(value, ~r/\A[[:xdigit:]]+\z/)

  defp valid_hex_value?(_value, _length), do: false

  defp parse_traceparent_fields(version, trace_id, span_id, flags) do
    if valid_version?(version) and valid_trace_id?(trace_id) and valid_span_id?(span_id) and valid_flags?(flags) do
      {:ok, String.downcase(trace_id), String.downcase(span_id), String.downcase(flags)}
    else
      {:error, :invalid_traceparent}
    end
  end

  defp current_otel_headers! do
    case Code.ensure_loaded(:otel_propagator_text_map) do
      {:module, _module} ->
        :otel_propagator_text_map.inject([])

      {:error, _reason} ->
        raise ArgumentError,
              "put_current_from_otel!/0 requires the OpenTelemetry API application"
    end
  end

  defp random_hex(bytes), do: bytes |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
  defp present_string(value) when is_binary(value) and value != "", do: value
  defp present_string(_value), do: nil
end
