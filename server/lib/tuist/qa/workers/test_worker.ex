defmodule Tuist.QA.Workers.TestWorker do
  @moduledoc """
  A worker that performs tests on a given app build and a given prompt.
  """
  use Oban.Worker,
    unique: [
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ],
    max_attempts: 1

  alias Tuist.QA

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"qa_run_id" => qa_run_id}} = _job) do
    {:ok, qa_run} = QA.qa_run(qa_run_id, preload: [app_build: [preview: [project: :account]]])

    {:ok, qa_run} = QA.test(qa_run)

    QA.post_vcs_test_summary(qa_run)
  end
end
