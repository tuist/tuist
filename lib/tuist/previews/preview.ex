defmodule Tuist.Previews.Preview do
  @moduledoc """
  A module that represents a preview.
  """
  alias Tuist.Projects.Project

  use Ecto.Schema
  import Ecto.Changeset

  @derive {
    Flop.Schema,
    filterable: [
      :project_id,
      :display_name,
      :git_branch,
      :git_commit_sha,
      :bundle_identifier
    ],
    sortable: [:inserted_at]
  }

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "previews" do
    belongs_to :project, Project
    belongs_to :ran_by_account, Tuist.Accounts.Account
    has_one :command_event, Tuist.CommandEvents.Event
    field :type, Ecto.Enum, values: [app_bundle: 0, ipa: 1]
    field :display_name, :string
    field :bundle_identifier, :string
    field :version, :string
    field :git_branch, :string
    field :git_commit_sha, :string

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

    timestamps(type: :utc_datetime)
  end

  def create_changeset(token, attrs) do
    token
    |> cast(attrs, [
      :project_id,
      :type,
      :display_name,
      :bundle_identifier,
      :version,
      :inserted_at,
      :supported_platforms,
      :git_branch,
      :git_commit_sha,
      :ran_by_account_id
    ])
    |> validate_subset(:supported_platforms, Ecto.Enum.values(__MODULE__, :supported_platforms))
    |> validate_required([:project_id, :type])
  end
end
