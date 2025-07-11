defmodule Tuist.CommandEvents.TestCaseRun do
  @moduledoc """
  Test action represents a single test case run, such as a `testExample()` method from an arbitrary test suite.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.CommandEvents.Event
  alias Tuist.CommandEvents.TestCase

  @derive {
    Flop.Schema,
    filterable: [:test_case_id], sortable: [:inserted_at]
  }

  schema "test_case_runs" do
    field :status, Ecto.Enum, values: [success: 0, failure: 1]
    field :flaky, :boolean, default: false
    field :xcode_target_id, :string

    belongs_to :command_event, Event, foreign_key: :command_event_id, references: :id, type: Ecto.UUID
    belongs_to :test_case, TestCase

    # credo:disable-for-next-line Credo.Checks.TimestampsType
    timestamps(updated_at: false)
  end

  def create_changeset(test_case_run, attrs) do
    test_case_run
    |> cast(attrs, [
      # :module_hash,
      :status,
      :command_event_id,
      :test_case_id,
      :xcode_target_id,
      :flaky,
      :inserted_at
    ])
    |> validate_required([
      :status,
      :command_event_id,
      :test_case_id,
      :xcode_target_id
    ])
    |> validate_inclusion(:status, [:success, :failure])
  end
end
