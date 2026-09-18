defmodule Atlas.Engineering.Errors.SummaryWorkerTest do
  use Atlas.DataCase, async: true

  import Mimic

  alias Atlas.Audit.Activity
  alias Atlas.Engineering.Errors.Summaries
  alias Atlas.Engineering.Errors.SummaryRun
  alias Atlas.Engineering.Errors.SummaryWorker

  setup :verify_on_exit!

  test "audits a delivered error summary" do
    run = %SummaryRun{
      id: Ecto.UUID.generate(),
      issue_count: 4,
      slack_channel_id: "C123"
    }

    stub(Summaries, :reconcile, fn opts ->
      assert opts[:retry?] == false
      assert opts[:scheduled_for] == ~U[2026-09-05 12:01:00Z]
      {:ok, run, :delivered}
    end)

    assert :ok =
             SummaryWorker.perform(%Oban.Job{
               attempt: 1,
               inserted_at: ~U[2026-09-05 12:01:42Z]
             })

    run_id = run.id

    assert %Activity{
             action: "error.summary.posted",
             interface: "worker",
             target_type: "error_summary",
             target_id: ^run_id
           } = Repo.get_by!(Activity, target_id: run.id)
  end

  test "retries a transient failure" do
    stub(Summaries, :reconcile, fn opts ->
      assert opts[:retry?]
      {:error, :temporary_failure}
    end)

    assert {:error, :temporary_failure} = SummaryWorker.perform(%Oban.Job{attempt: 2})
  end

  test "cancels a provider credit failure" do
    stub(Summaries, :reconcile, fn opts ->
      refute opts[:retry?]
      {:error, :llm_credit_limit}
    end)

    assert {:cancel, :llm_credit_limit} = SummaryWorker.perform(%Oban.Job{attempt: 1})
  end
end
