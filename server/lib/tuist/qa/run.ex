defmodule Tuist.QA.Run do
  @moduledoc """
  Schema for QA runs.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.AppBuilds.AppBuild
  alias Tuist.QA.Recording
  alias Tuist.QA.Screenshot
  alias Tuist.QA.Step

  @derive {
    Flop.Schema,
    filterable: [
      :id,
      :status,
      :git_ref
    ],
    sortable: [:inserted_at, :finished_at]
  }

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7
  schema "qa_runs" do
    field :prompt, :string
    field :status, :string, default: "pending"
    field :git_ref, :string
    field :issue_comment_id, :integer
    field :finished_at, :utc_datetime
    field :launch_argument_groups, {:array, :map}, default: []
    field :app_description, :string, default: ""
    field :email, :string, default: ""
    field :password, :string, default: ""

    belongs_to :app_build, AppBuild, type: UUIDv7
    has_one :recording, Recording, foreign_key: :qa_run_id
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
      :git_ref,
      :issue_comment_id,
      :launch_argument_groups,
      :app_description,
      :email,
      :password
    ])
    |> validate_required([:prompt, :status])
    |> validate_inclusion(:status, ["pending", "running", "completed", "failed"])
    |> foreign_key_constraint(:app_build_id)
  end

  def update_changeset(qa_run, attrs) do
    cast(qa_run, attrs, [
      :app_build_id,
      :status,
      :finished_at,
      :launch_argument_groups,
      :app_description,
      :email,
      :password
    ])
  end
end
