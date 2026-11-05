defmodule Pulse.LogQL.QuantileReferenceTest do
  use Pulse.Test.Case, async: true

  alias Pulse.LogQL.Quantile
  alias Pulse.PromQL.FloatParser

  test "pinned Loki v3.6.6 interpolation reference including IEEE edges" do
    cases = Pulse.JSON.decode!(File.read!("test/fixtures/alerting/loki-quantiles.json"))
    assert length(cases) == 63

    for sample <- cases do
      actual = Quantile.calculate(number(sample["q"]), Enum.map(sample["values"], &number/1))
      expected = number(sample["expected"])

      if is_float(actual) and is_float(expected) and expected != 0.0 do
        assert_in_delta actual, expected, max(abs(expected) * 1.0e-14, 4.9406564584124654e-324), inspect(sample)
      else
        assert :erlang.term_to_binary(actual) == :erlang.term_to_binary(expected), inspect(sample)
      end
    end
  end

  defp number(text) do
    {:ok, value} = FloatParser.parse(text)
    value
  end
end
