defmodule Tuist.Automations.Types.FlakinessRateType do
  @moduledoc false
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Tests.TestCase
  alias Tuist.Tests.TestCaseRun

  def evaluate(automation) do
    config = automation.config
    threshold = config["threshold"] || 10
    window = parse_window(config["window"] || "30d")
    project_id = automation.project_id

    cutoff = DateTime.add(DateTime.utc_now(), -window, :second)

    flakiness_rates =
      ClickHouseRepo.all(
        from(tcr in TestCaseRun,
          where: tcr.project_id == ^project_id,
          where: tcr.inserted_at >= ^cutoff,
          group_by: tcr.test_case_id,
          having: count(tcr.id) > 0,
          select: %{
            test_case_id: tcr.test_case_id,
            flakiness_rate: fragment("countIf(?) * 100.0 / count()", tcr.is_flaky)
          }
        )
      )

    triggered_test_case_ids =
      flakiness_rates
      |> Enum.filter(fn %{flakiness_rate: rate} -> rate >= threshold end)
      |> Enum.map(& &1.test_case_id)

    all_test_case_ids =
      ClickHouseRepo.all(from(tc in TestCase, hints: ["FINAL"], where: tc.project_id == ^project_id, select: tc.id))

    %{
      triggered: triggered_test_case_ids,
      all: all_test_case_ids
    }
  end

  defp parse_window(window) when is_binary(window) do
    case Integer.parse(window) do
      {value, "d"} -> value * 86_400
      {value, "h"} -> value * 3600
      {value, "m"} -> value * 60
      _ -> 30 * 86_400
    end
  end

  defp parse_window(_), do: 30 * 86_400
end
