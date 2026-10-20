defmodule Atlas.Engineering.Projects.Webhook do
  @moduledoc """
  Per-project inbound webhook for an external source.

  The plaintext token is generated once when the webhook is created, shown
  to the user, and never stored. Only its SHA-256 hash lives in the
  database.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Atlas.Engineering.Projects.Project

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @sources [:grafana]

  schema "project_webhooks" do
    field :name, :string
    field :source, Ecto.Enum, values: @sources
    field :token_hash, :string
    field :last_used_at, :utc_datetime

    belongs_to :project, Project

    timestamps(type: :utc_datetime)
  end

  def sources, do: @sources

  def source_label(:grafana), do: "Grafana"

  def changeset(webhook, attrs) do
    webhook
    |> cast(attrs, [:name, :source, :token_hash, :project_id])
    |> validate_required([:name, :source, :token_hash, :project_id])
    |> validate_length(:name, max: 120)
    |> validate_inclusion(:source, @sources)
    |> unique_constraint(:token_hash)
  end
end
