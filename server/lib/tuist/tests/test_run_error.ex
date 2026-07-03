defmodule Tuist.Tests.TestRunError do
  @moduledoc """
  A run/target-level error that isn't a test failure: the test runner itself
  errored (for example a target whose `.xctest` bundle couldn't be loaded, or
  the app under test couldn't launch). xcresult surfaces these as synthetic
  "xctest (<pid>) encountered an error" cases; we lift them out of the test
  cases and store them here — modelled the way Xcode's "Errors" section does —
  so they don't inflate the test counts or fan out `test_case.created` webhooks.

  Stored in ClickHouse and associated to a `Tuist.Tests.Test` via `test_run_id`.
  `module_name` is the test target, or empty for a run-level error.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "test_run_errors" do
    field :test_run_id, Ecto.UUID
    field :project_id, Ch, type: "Int64"
    field :module_name, Ch, type: "String"
    field :message, Ch, type: "String"
    field :inserted_at, Ch, type: "DateTime64(6)"

    belongs_to :test_run, Tuist.Tests.Test, foreign_key: :test_run_id, define_field: false
  end

  def create_changeset(error, attrs) do
    error
    |> cast(attrs, [:id, :test_run_id, :project_id, :module_name, :message, :inserted_at])
    |> validate_required([:id, :test_run_id, :message])
  end
end
