defmodule Tuist.QA.Run do
  @moduledoc """
  Schema for QA runs.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.AppBuilds.AppBuild
  alias Tuist.QA.Screenshot
  alias Tuist.QA.Step

  @derive {
    Flop.Schema,
    filterable: [
      :id,
      :status,
      :vcs_provider,
      :git_ref
    ],
    sortable: [:inserted_at, :finished_at]
  }

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7
  schema "qa_runs" do
    field :prompt, :string
    field :status, :string, default: "pending"
    field :vcs_repository_full_handle, :string
    field :vcs_provider, Ecto.Enum, values: [github: 0]
    field :git_ref, :string
    field :issue_comment_id, :integer
    field :finished_at, :utc_datetime

    belongs_to :app_build, AppBuild, type: UUIDv7
    has_many :run_steps, Step, foreign_key: :qa_run_id
    has_many :screenshots, Screenshot, foreign_key: :qa_run_id

    timestamps(type: :utc_datetime)
  end

  def create_changeset(qa_run, attrs) do
    qa_run
    |> cast(attrs, [
      :app_build_id,
      :prompt,
      :status,
      :vcs_repository_full_handle,
      :vcs_provider,
      :git_ref,
      :issue_comment_id
    ])
    |> validate_required([:prompt, :status])
    |> validate_inclusion(:status, ["pending", "running", "completed", "failed"])
    |> foreign_key_constraint(:app_build_id)
  end

  def update_changeset(qa_run, attrs) do
    cast(qa_run, attrs, [:app_build_id, :status, :finished_at])
  end
end
