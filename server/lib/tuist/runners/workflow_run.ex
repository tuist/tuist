defmodule Tuist.Runners.WorkflowRun do
  @moduledoc false
  use Ecto.Schema

  schema "runner_github_workflow_runs" do
    belongs_to(:account, Tuist.Accounts.Account)
    field(:workflow_run_id, :integer)
    field(:run_attempt, :integer)
    field(:run, :map)
    timestamps(type: :utc_datetime)
  end
end
