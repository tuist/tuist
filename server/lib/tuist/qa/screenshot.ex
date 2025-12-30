defmodule Tuist.QA.Screenshot do
  @moduledoc """
  Schema for QA screenshots.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.QA.Run
  alias Tuist.QA.Step

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7

  schema "qa_screenshots" do
    belongs_to :qa_run, Run, foreign_key: :qa_run_id, type: UUIDv7
    belongs_to :qa_step, Step, foreign_key: :qa_step_id, type: UUIDv7

    timestamps(type: :utc_datetime)
  end

  def changeset(screenshot, attrs) do
    screenshot
    |> cast(attrs, [:qa_run_id, :qa_step_id])
    |> validate_required([:qa_run_id])
    |> foreign_key_constraint(:qa_run_id)
    |> foreign_key_constraint(:qa_step_id)
  end
end
