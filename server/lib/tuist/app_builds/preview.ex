defmodule Tuist.AppBuilds.Preview do
  @moduledoc """
  A module that represents a preview.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Projects.Project

  @derive {
    Flop.Schema,
    filterable: [
      :project_id,
      :display_name,
      :git_branch,
      :git_commit_sha,
      :bundle_identifier,
      :track
    ],
    sortable: [:inserted_at, :bundle_identifier]
  }

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "previews" do
    has_many :app_builds, Tuist.AppBuilds.AppBuild
    belongs_to :project, Project
    belongs_to :created_by_account, Tuist.Accounts.Account
    field :display_name, :string
    field :bundle_identifier, :string
    field :version, :string
    field :git_branch, :string
    field :git_commit_sha, :string
    field :git_ref, :string
    field :track, :string, default: ""

    field :supported_platforms, {:array, Ecto.Enum},
      values: [
        ios: 0,
        ios_simulator: 1,
        tvos: 2,
        tvos_simulator: 3,
        watchos: 4,
        watchos_simulator: 5,
        visionos: 6,
        visionos_simulator: 7,
        macos: 8
      ]

    field :visibility, Ecto.Enum,
      values: [
        public: 0,
        private: 1
      ]

    timestamps(type: :utc_datetime)
  end

  def create_changeset(token, attrs) do
    token
    |> cast(attrs, [
      :project_id,
      :display_name,
      :bundle_identifier,
      :version,
      :inserted_at,
      :git_branch,
      :git_commit_sha,
      :git_ref,
      :created_by_account_id,
      :supported_platforms,
      :visibility,
      :track
    ])
    |> validate_subset(:supported_platforms, Ecto.Enum.values(__MODULE__, :supported_platforms))
    |> validate_required([:project_id])
  end

  def map_simulators_to_devices(platforms) do
    platforms
    |> Enum.map(&simulator_to_device/1)
    |> Enum.uniq()
  end

  def simulator_to_device(platform) do
    case platform do
      :ios_simulator -> :ios
      :tvos_simulator -> :tvos
      :watchos_simulator -> :watchos
      :visionos_simulator -> :visionos
      other -> other
    end
  end
end
