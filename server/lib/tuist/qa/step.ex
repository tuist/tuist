defmodule Tuist.QA.Step do
  @moduledoc """
  Schema for QA run steps.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.QA.Run
  alias Tuist.QA.Screenshot

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7

  schema "qa_steps" do
    field :action, :string
    field :result, :string
    field :issues, {:array, :string}
    field :started_at, :utc_datetime

    belongs_to :qa_run, Run, foreign_key: :qa_run_id, type: UUIDv7
    has_one :screenshot, Screenshot, foreign_key: :qa_step_id

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(qa_step, attrs) do
    qa_step
    |> cast(attrs, [:qa_run_id, :action, :result, :issues, :started_at])
    |> validate_required([:qa_run_id, :action, :issues])
    |> foreign_key_constraint(:qa_run_id)
  end
end
