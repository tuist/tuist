defmodule Atlas.Integrations.GitHubApp do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Encrypted.Binary
  alias Atlas.Integrations.GitHubRepository

  schema "github_apps" do
    field :name, :string
    field :webhook_secret, Binary
    field :app_id, :string
    field :private_key, Binary
    field :installation_id, :string

    has_many :repositories, GitHubRepository, foreign_key: :github_app_id

    timestamps()
  end

  def changeset(app, attrs) do
    app
    |> cast(attrs, [:name, :webhook_secret, :app_id, :private_key, :installation_id])
    |> validate_required([:name, :webhook_secret, :app_id, :private_key, :installation_id])
  end
end
