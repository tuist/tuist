defmodule Atlas.GTM.SocialAccount do
  @moduledoc """
  A brand or personal social account Atlas reads post metrics from. The grant
  belongs to Atlas, not to the person who connected it, so the account keeps
  syncing whoever leaves; `connected_by` is only a record of who added it.
  """

  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Encrypted.Binary
  alias Atlas.Users.User

  @kinds ~w(brand personal)

  def kinds, do: @kinds

  schema "social_accounts" do
    field :platform, :string
    field :external_id, :string
    field :handle, :string
    field :kind, :string
    field :access_token, Binary, redact: true
    field :refresh_token, Binary, redact: true
    field :scopes, {:array, :string}, default: []
    field :expires_at, :utc_datetime
    field :needs_authorization, :boolean, default: false
    field :last_synced_at, :utc_datetime

    belongs_to :connected_by, User

    timestamps(type: :utc_datetime)
  end

  def changeset(account, attrs) do
    account
    |> cast(attrs, [:handle, :kind, :access_token, :refresh_token, :scopes, :expires_at, :needs_authorization])
    |> validate_required([:platform, :external_id, :handle, :kind, :access_token])
    |> validate_inclusion(:platform, ["x"])
    |> validate_inclusion(:kind, @kinds)
    |> unique_constraint([:platform, :external_id])
  end

  def expired?(%__MODULE__{expires_at: nil}), do: false

  def expired?(%__MODULE__{expires_at: expires_at}) do
    not DateTime.after?(expires_at, DateTime.add(DateTime.utc_now(), 120, :second))
  end
end
