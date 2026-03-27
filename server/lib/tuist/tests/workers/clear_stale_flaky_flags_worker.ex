defmodule Tuist.Tests.Workers.ClearStaleFlakyFlagsWorker do
  @moduledoc """
  A scheduled worker that enqueues a ClearCooledDownFlakyTestsWorker
  for each project that has flaky test cases.
  """
  use Oban.Worker

  import Ecto.Query

  alias Tuist.Tests.Workers.ClearCooledDownFlakyTestsWorker

  @impl Oban.Worker
  def perform(_args) do
    project_ids =
      Tuist.ClickHouseRepo.all(
        from(test_case in Tuist.Tests.TestCase,
          hints: ["FINAL"],
          where: test_case.is_flaky == true,
          select: test_case.project_id,
          distinct: true
        )
      )

    project_ids
    |> Enum.map(fn project_id ->
      ClearCooledDownFlakyTestsWorker.new(%{project_id: project_id})
    end)
    |> Oban.insert_all()

    :ok
  end
end
