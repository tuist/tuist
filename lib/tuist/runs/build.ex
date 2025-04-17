defmodule Tuist.Runs.Build do
  @moduledoc """
  A build represents a single build run of a project, such as when building an app from Xcode.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @derive {
    Flop.Schema,
    filterable: [
      :project_id
    ],
    sortable: [:inserted_at]
  }

  @primary_key {:id, UUIDv7, autogenerate: false}
  schema "build_runs" do
    field :duration, :integer
    field :macos_version, :string
    field :xcode_version, :string
    field :is_ci, :boolean
    field :model_identifier, :string
    field :scheme, :string
    field :status, Ecto.Enum, values: [success: 0, failure: 1]
    belongs_to :project, Tuist.Projects.Project
    belongs_to :ran_by_account, Tuist.Accounts.Account, foreign_key: :account_id

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def create_changeset(build, attrs) do
    build
    |> cast(attrs, [
      :id,
      :duration,
      :macos_version,
      :xcode_version,
      :is_ci,
      :model_identifier,
      :scheme,
      :project_id,
      :account_id,
      :inserted_at,
      :status
    ])
    |> validate_required([
      :id,
      :duration,
      :is_ci,
      :project_id,
      :account_id,
      :status
    ])
    |> validate_inclusion(:status, [:success, :failure])
  end
end
