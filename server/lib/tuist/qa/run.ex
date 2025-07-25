defmodule Tuist.QA.Run do
  @moduledoc """
  Schema for QA runs.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Association.NotLoaded
  alias Tuist.AppBuilds.AppBuild
  alias Tuist.QA.RunStep

  @type t :: %__MODULE__{
          id: binary(),
          app_build_id: binary(),
          app_build: AppBuild.t() | NotLoaded.t(),
          prompt: String.t(),
          status: String.t(),
          summary: String.t() | nil,
          run_steps: [RunStep.t()] | NotLoaded.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7

  schema "qa_runs" do
    field :prompt, :string
    field :status, :string, default: "pending"
    field :summary, :string

    belongs_to :app_build, AppBuild, type: UUIDv7
    has_many :run_steps, RunStep, foreign_key: :qa_run_id

    timestamps(type: :utc_datetime)
  end

  def create_changeset(qa_run, attrs) do
    qa_run
    |> cast(attrs, [:app_build_id, :prompt, :status, :summary])
    |> validate_required([:app_build_id, :prompt, :status])
    |> validate_inclusion(:status, ["pending", "running", "completed", "failed"])
    |> foreign_key_constraint(:app_build_id)
  end

  def update_changeset(qa_run, attrs) do
    cast(qa_run, attrs, [:status])
  end
end
