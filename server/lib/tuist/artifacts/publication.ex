defmodule Tuist.Artifacts.Publication do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "artifact_publications" do
    belongs_to :project, Tuist.Projects.Project
    belongs_to :created_by_account, Tuist.Accounts.Account
    field :key, :string
    field :intent, :map
    field :contents, :map
    field :committed, :boolean, default: false
    field :projected, :boolean, default: false
    field :expired, :boolean, default: false
    timestamps(type: :utc_datetime)
  end
end
