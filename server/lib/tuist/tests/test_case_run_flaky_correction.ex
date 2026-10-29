defmodule Tuist.Tests.TestCaseRunFlakyCorrection do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:test_case_run_id, Ecto.UUID, autogenerate: false}

  schema "test_case_run_flaky_corrections" do
    field :project_id, :integer
    field :test_case_id, Ecto.UUID
    field :git_commit_sha, :string
    field :state, :string, default: "pending"

    timestamps(type: :utc_datetime)
  end
end
