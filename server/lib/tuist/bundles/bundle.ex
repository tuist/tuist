defmodule Tuist.Bundles.Bundle do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Bundles.Artifact

  @derive {
    Flop.Schema,
    filterable: [
      :project_id,
      :git_branch,
      :type,
      :name,
      :install_size,
      :download_size,
      :supported_platforms
    ],
    sortable: [:inserted_at, :install_size, :download_size]
  }

  @primary_key {:id, UUIDv7, autogenerate: false}
  @foreign_key_type UUIDv7
  schema "bundles" do
    field :app_bundle_id, :string
    field :name, :string
    field :install_size, :integer
    field :download_size, :integer
    field :git_branch
    field :git_commit_sha
    field :git_ref

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

    field :version, :string

    field :type, Ecto.Enum,
      values: [
        ipa: 0,
        app: 1,
        xcarchive: 2
      ]

    belongs_to :project, Tuist.Projects.Project, type: :integer
    belongs_to :uploaded_by_account, Tuist.Accounts.Account, type: :integer
    has_many :artifacts, Artifact

    timestamps(type: :utc_datetime)
  end

  def changeset(bundle, attrs) do
    bundle
    |> cast(attrs, [
      :id,
      :app_bundle_id,
      :name,
      :install_size,
      :download_size,
      :supported_platforms,
      :version,
      :type,
      :project_id,
      :uploaded_by_account_id,
      :git_commit_sha,
      :git_branch,
      :git_ref,
      :inserted_at
    ])
    |> validate_required([
      :app_bundle_id,
      :name,
      :install_size,
      :supported_platforms,
      :version,
      :type,
      :project_id
    ])
    |> validate_subset(:supported_platforms, Ecto.Enum.values(__MODULE__, :supported_platforms))
    |> foreign_key_constraint(:project_id)
  end
end
