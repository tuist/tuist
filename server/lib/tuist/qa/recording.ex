defmodule Tuist.QA.Recording do
  @moduledoc """
  Schema for QA run recordings.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.QA.Run

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7
  schema "qa_recordings" do
    field :started_at, :utc_datetime
    field :duration, :integer

    belongs_to :qa_run, Run, type: UUIDv7

    timestamps(type: :utc_datetime)
  end

  def create_changeset(recording, attrs) do
    recording
    |> cast(attrs, [:qa_run_id, :started_at, :duration])
    |> validate_required([:qa_run_id, :started_at, :duration])
    |> foreign_key_constraint(:qa_run_id)
  end
end
