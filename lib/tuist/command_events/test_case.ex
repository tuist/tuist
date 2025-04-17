defmodule Tuist.CommandEvents.TestCase do
  @moduledoc """
  Test case represents a test case (represented by a function in Swift) from an arbitrary test suite, such as `testExample()`.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.CommandEvents.TestCaseRun
  alias Tuist.Projects.Project

  @derive {
    Flop.Schema,
    filterable: [],
    sortable: [:last_flaky_test_case_run_inserted_at],
    adapter_opts: [
      join_fields: [
        last_flaky_test_case_run_inserted_at: [
          binding: :last_flaky_test_case_run,
          field: :inserted_at,
          path: [:last_flaky_test_case_run, :inserted_at]
        ]
      ]
    ]
  }

  schema "test_cases" do
    field :name, :string
    field :module_name, :string
    field :identifier, :string
    field :project_identifier, :string
    field :flaky, :boolean, default: false

    belongs_to :project, Project
    has_one :last_flaky_test_case_run, TestCaseRun

    # credo:disable-for-next-line Credo.Checks.TimestampsType
    timestamps(updated_at: false)
  end

  def create_changeset(test_case_run, attrs) do
    test_case_run
    |> cast(attrs, [
      :name,
      :module_name,
      :project_identifier,
      :identifier,
      :project_id,
      :flaky,
      :inserted_at
    ])
    |> validate_required([
      :name,
      :module_name,
      :project_identifier,
      :identifier,
      :project_id
    ])
  end
end
