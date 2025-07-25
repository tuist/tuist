defmodule Tuist.QA.RunStep do
  @moduledoc """
  Schema for QA run steps.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.QA.Run

  @type t :: %__MODULE__{
          id: binary(),
          qa_run_id: binary(),
          qa_run: Run.t() | Ecto.Association.NotLoaded.t(),
          summary: String.t(),
          inserted_at: DateTime.t()
        }

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7

  schema "qa_run_steps" do
    field :summary, :string
    
    belongs_to :qa_run, Run, foreign_key: :qa_run_id, type: UUIDv7

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(qa_run_step, attrs) do
    qa_run_step
    |> cast(attrs, [:qa_run_id, :summary])
    |> validate_required([:qa_run_id, :summary])
    |> foreign_key_constraint(:qa_run_id)
  end
end