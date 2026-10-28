defmodule Atlas.Signals.Source do
  @moduledoc false
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Automations.Revision
  alias Atlas.Encrypted.Binary
  alias Atlas.Users.User

  schema "signal_sources" do
    field :name, :string
    field :enabled, :boolean, default: false
    field :reader_ids, {:array, Ecto.UUID}, default: []
    field :required_scopes, {:array, :string}, default: []
    field :routing_roles, {:array, :string}, default: []
    field :event_receiver, :map
    field :signing_secret, Binary, redact: true
    field :delivery, :map, virtual: true, redact: true
    field :poll_config, Binary, redact: true
    field :poll_state, Binary, redact: true
    field :poll_interval_seconds, :integer
    field :poll_next_at, :utc_datetime_usec
    field :poll_error, :string
    belongs_to :owner, User
    belongs_to :revision, Revision
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(source, attrs) do
    source
    |> cast(attrs, [:name, :reader_ids, :required_scopes, :routing_roles, :event_receiver])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 120)
    |> foreign_key_constraint(:revision_id)
  end
end
