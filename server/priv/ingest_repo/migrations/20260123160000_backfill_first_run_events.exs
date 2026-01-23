defmodule Tuist.IngestRepo.Migrations.BackfillFirstRunEvents do
  @moduledoc """
  Backfills first_run events for all existing test cases based on their earliest test_case_run.
  Uses the same deterministic UUID generation as TestCaseEvent.first_run_id/1.
  """
  use Ecto.Migration
  alias Tuist.IngestRepo
  alias Tuist.Runs.TestCaseEvent
  import Ecto.Query
  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true
  @batch_size 10_000
  @throttle_ms 500

  def up do
    Logger.info("Backfilling first_run events for existing test cases...")
    throttle_change_in_batches(&page_query/1, &do_change/1)
  end

  def down do
    :ok
  end

  defp page_query(last_test_case_id) do
    from(
      tcr in "test_case_runs",
      select: %{
        test_case_id: tcr.test_case_id,
        first_ran_at: min(tcr.ran_at)
      },
      where: not is_nil(tcr.test_case_id) and tcr.test_case_id > ^last_test_case_id,
      group_by: tcr.test_case_id,
      order_by: [asc: tcr.test_case_id],
      limit: @batch_size
    )
  end

  defp do_change(batch) do
    now = NaiveDateTime.utc_now()

    events =
      Enum.map(batch, fn %{
                           test_case_id: test_case_id,
                           first_ran_at: first_ran_at
                         } ->
        %{
          id: TestCaseEvent.first_run_id(test_case_id),
          test_case_id: test_case_id,
          event_type: "first_run",
          actor_id: nil,
          inserted_at: first_ran_at || now
        }
      end)

    IngestRepo.insert_all("test_case_events", events,
      types: %{
        id: :uuid,
        test_case_id: :uuid,
        event_type: "LowCardinality(String)",
        actor_id: "Nullable(Int64)",
        inserted_at: "DateTime64(6)"
      }
    )

    Logger.info("Inserted #{length(events)} first_run events")

    batch
  end

  defp throttle_change_in_batches(
         query_fun,
         change_fun,
         last_test_case_id \\ "00000000-0000-0000-0000-000000000000"
       )

  defp throttle_change_in_batches(query_fun, change_fun, last_test_case_id) do
    case IngestRepo.all(query_fun.(last_test_case_id), log: :info, timeout: :infinity) do
      [] ->
        Logger.info("Backfill complete, running OPTIMIZE to deduplicate...")

        {:ok, _} =
          IngestRepo.query(
            "OPTIMIZE TABLE test_case_events FINAL",
            [],
            timeout: :infinity
          )

        Logger.info("OPTIMIZE complete")
        :ok

      batch ->
        change_fun.(batch)
        next_test_case_id = batch |> List.last() |> Map.get(:test_case_id) |> Ecto.UUID.cast!()
        Process.sleep(@throttle_ms)
        throttle_change_in_batches(query_fun, change_fun, next_test_case_id)
    end
  end
end
