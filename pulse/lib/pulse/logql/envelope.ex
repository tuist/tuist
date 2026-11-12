defmodule Pulse.LogQL.Envelope do
  @moduledoc """
  Marshal `Pulse.LogQL.Evaluator` results into the Loki HTTP wire
  format: `{status: "success", data: {resultType, result: [...]}}`.

  Shared by `PulseWeb.LokiQueryController` and `Pulse.MCP.Tools`
  (`query_logql`) so both surfaces emit byte-identical payloads.

    * Streams entries use nanosecond timestamp strings.
    * Matrix and vector samples are `[<seconds as a JSON number>, "<value>"]`,
      as Loki documents and Grafana decodes them.
  """

  alias Pulse.PromQL.Evaluator
  alias Pulse.PromQL.Time

  @spec scalar([{map(), {integer(), term()}}], [String.t()]) :: map()
  def scalar([{_labels, {ts, value}}], encoding_flags \\ []) do
    %{
      "status" => "success",
      "data" => %{"resultType" => "scalar", "result" => [seconds_str(ts), value_str(value)], "stats" => %{}}
    }
    |> with_encoding_flags(encoding_flags)
  end

  @spec streams([Pulse.LogQL.Evaluator.stream()], [String.t()]) :: map()
  def streams(streams, encoding_flags \\ []) when is_list(streams) do
    result =
      Enum.map(streams, fn {labels, entries} ->
        %{
          "stream" => stringify(labels),
          "values" => Enum.map(entries, &stream_value/1)
        }
      end)

    %{
      "status" => "success",
      "data" => %{
        "resultType" => "streams",
        "result" => result,
        "stats" => %{}
      }
    }
    |> with_encoding_flags(encoding_flags)
  end

  @spec matrix([{map(), [{integer(), float()}]}], [String.t()]) :: map()
  def matrix(series, encoding_flags \\ []) when is_list(series) do
    result =
      Enum.map(series, fn {labels, samples} ->
        %{
          "metric" => stringify(labels),
          "values" => Enum.map(samples, fn {ts, v} -> [seconds_str(ts), value_str(v)] end)
        }
      end)

    %{
      "status" => "success",
      "data" => %{
        "resultType" => "matrix",
        "result" => result,
        "stats" => %{}
      }
    }
    |> with_encoding_flags(encoding_flags)
  end

  @spec vector([{map(), {integer(), float()}}], [String.t()]) :: map()
  def vector(series, encoding_flags \\ []) when is_list(series) do
    result =
      Enum.map(series, fn {labels, {ts, v}} ->
        %{
          "metric" => stringify(labels),
          "value" => [seconds_str(ts), value_str(v)]
        }
      end)

    %{
      "status" => "success",
      "data" => %{
        "resultType" => "vector",
        "result" => result,
        "stats" => %{}
      }
    }
    |> with_encoding_flags(encoding_flags)
  end

  defp stream_value({ts, line}), do: [Integer.to_string(ts), line]
  defp stream_value({ts, line, categories}), do: [Integer.to_string(ts), line, categories]

  defp with_encoding_flags(envelope, []), do: envelope
  defp with_encoding_flags(envelope, flags), do: put_in(envelope, ["data", "encodingFlags"], flags)

  defp stringify(map) when is_map(map), do: Map.new(map, fn {k, v} -> {to_string(k), to_string(v)} end)

  # Like Loki and Prometheus: the timestamp is a JSON number of seconds and
  # the value is Go-formatted text. Grafana decodes the timestamp as a float.
  defp seconds_str(ts_ns) when is_integer(ts_ns), do: Time.seconds(ts_ns)

  defp value_str(v), do: Evaluator.format_value(v)
end
