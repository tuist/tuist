defmodule TuistCloud.CommandEvents.TestCaseRun do
  @moduledoc """
  Test action represents a single test case run, such as a `testExample()` method from an arbitrary test suite.
  """
  alias TuistCloud.CommandEvents.Event
  use Ecto.Schema
  import Ecto.Changeset

  schema "test_case_runs" do
    field :name, :string
    field :module_name, :string
    field :identifier, :string
    field :project_identifier, :string
    field :module_hash, :string
    field :status, Ecto.Enum, values: [success: 0, failure: 1, unknown: 2]

    belongs_to :command_event, Event

    timestamps(updated_at: false)
  end

  def create_changeset(test_case_run, attrs) do
    test_case_run
    |> cast(attrs, [
      :name,
      :module_name,
      :project_identifier,
      :module_hash,
      :identifier,
      :status,
      :command_event_id
    ])
    |> validate_required([
      :name,
      :module_name,
      :project_identifier,
      :module_hash,
      :identifier,
      :status,
      :command_event_id
    ])
    |> validate_inclusion(:status, [:success, :failure])
  end
end
