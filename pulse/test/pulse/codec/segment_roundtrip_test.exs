defmodule Pulse.Codec.SegmentRoundtripTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Record.Log
  alias Pulse.Record.MetricSample
  alias Pulse.Storage.S3

  defp identifier(i), do: :crypto.hash(:sha256, <<i::64>>) |> Base.encode16(case: :lower)

  test "log identifiers remain lossless across missing, shared, and high-entropy distributions" do
    for n <- [50, 2500, 15_000], shape <- [:missing, :shared, :unique] do
      input =
        for i <- 1..n do
          key = if shape == :shared, do: div(i, 100), else: i

          %Log{
            timestamp_ns: 1_700_000_000_000_000_000 + i * 117_821,
            service: "worker",
            severity_text: "INFO",
            body: "processed event #{rem(i, 31)}",
            trace_id: if(shape != :missing, do: identifier(key)),
            span_id: if(shape != :missing, do: String.slice(identifier(div(key, 2)), 0, 16)),
            resource: %{"host" => "node-1"}
          }
        end

      assert {:ok, blob, _, _} = S3.encode_segment(:logs, input)
      assert {:ok, decoded} = S3.decode_segment(:logs, blob, nil, nil, [])
      assert Enum.sort(decoded) == Enum.sort(input)
    end
  end

  test "metric values and selective reads survive different series distributions" do
    for n <- [50, 2500, 15_000],
        shape <- [:repeated_gauge, :changing_counter, :float_entropy, :single_long_series] do
      input =
        for i <- 1..n do
          value =
            case shape do
              :repeated_gauge -> rem(i, 5) / 1
              :float_entropy -> :math.sin(i * 1.23456789) * 99_999.12345
              _ -> i / 1
            end

          %MetricSample{
            timestamp_ns: 1_700_000_000_000_000_000 + i * 15_000_000_000,
            value: value,
            labels: %{
              "__name__" => "work",
              "host" => "node-#{if(shape == :single_long_series, do: 0, else: rem(i, 100))}"
            }
          }
        end

      assert {:ok, blob, _, _} = S3.encode_segment(:metrics, input)
      assert {:ok, decoded} = S3.decode_segment(:metrics, blob, nil, nil, [])
      assert Enum.sort(Enum.map(decoded, &sample_fields/1)) == Enum.sort(Enum.map(input, &sample_fields/1))

      expected = Enum.at(decoded, div(n, 2))
      assert {:ok, [^expected]} = S3.decode_segment(:metrics, blob, expected.timestamp_ns, expected.timestamp_ns, [])
    end
  end

  defp sample_fields(sample), do: {sample.timestamp_ns, sample.labels, sample.value}
end
