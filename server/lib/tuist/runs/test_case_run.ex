defmodule Tuist.Runs.TestCaseRun do
  @moduledoc """
  A test case run represents execution of a single test case.
  This is a ClickHouse entity that stores test case run data.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @derive {
    Flop.Schema,
    filterable: [
      :test_run_id,
      :test_module_run_id,
      :test_suite_run_id,
      :test_case_id,
      :name,
      :status,
      :duration,
      :is_ci,
      :account_id,
      :scheme
    ],
    sortable: [:inserted_at, :duration, :name, :ran_at]
  }

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "test_case_runs" do
    field :name, :string
    field :test_run_id, Ecto.UUID
    field :test_module_run_id, Ecto.UUID
    field :test_suite_run_id, Ecto.UUID
    field :test_case_id, Ch, type: "Nullable(UUID)"
    field :project_id, Ch, type: "Nullable(Int64)"
    field :is_ci, :boolean, default: false
    field :scheme, :string, default: ""
    field :account_id, Ch, type: "Nullable(Int64)"
    field :ran_at, Ch, type: "Nullable(DateTime64(6))"
    field :git_branch, :string, default: ""
    field :status, Ch, type: "Enum8('success' = 0, 'failure' = 1, 'skipped' = 2)"
    field :duration, Ch, type: "Int32"
    field :inserted_at, Ch, type: "DateTime64(6)"
    field :module_name, Ch, type: "String"
    field :suite_name, Ch, type: "String"

    belongs_to :ran_by_account, Tuist.Accounts.Account, foreign_key: :account_id, define_field: false
  end

  def create_changeset(test_case_run, attrs) do
    test_case_run
    |> cast(attrs, [
      :id,
      :name,
      :test_run_id,
      :test_module_run_id,
      :test_suite_run_id,
      :test_case_id,
      :project_id,
      :is_ci,
      :scheme,
      :account_id,
      :ran_at,
      :git_branch,
      :status,
      :duration,
      :inserted_at,
      :module_name,
      :suite_name
    ])
    |> validate_required([
      :id,
      :name,
      :test_run_id,
      :test_module_run_id,
      :status,
      :duration,
      :module_name,
      :suite_name
    ])
    |> validate_inclusion(:status, ["success", "failure", "skipped"])
  end
end
