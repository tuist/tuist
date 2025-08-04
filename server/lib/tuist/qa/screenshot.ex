defmodule Tuist.QA.Screenshot do
  @moduledoc """
  Schema for QA screenshots.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.QA.Run
  alias Tuist.QA.RunStep

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7

  schema "qa_screenshots" do
    field :file_name, :string
    field :title, :string

    belongs_to :qa_run, Run, foreign_key: :qa_run_id, type: UUIDv7
    belongs_to :qa_run_step, RunStep, foreign_key: :qa_run_step_id, type: UUIDv7

    timestamps(type: :utc_datetime)
  end

  def changeset(screenshot, attrs) do
    screenshot
    |> cast(attrs, [:qa_run_id, :qa_run_step_id, :file_name, :title])
    |> validate_required([:qa_run_id, :file_name, :title])
    |> foreign_key_constraint(:qa_run_id)
    |> foreign_key_constraint(:qa_run_step_id)
    |> unique_constraint(:file_name, name: :qa_screenshots_qa_run_id_file_name_index)
  end
end
