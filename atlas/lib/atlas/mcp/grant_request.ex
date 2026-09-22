defmodule Atlas.MCP.GrantRequest do
  @moduledoc """
  A pending request for an operator grant, created when someone is sent to the
  ops reason form and consumed when they come back.

  Its id travels as `state` on the round trip. The grant arrives on an ordinary
  authenticated GET, so without this the callback would accept any readable
  token a link happened to carry, and storing it would displace a working grant.
  Consuming the row makes the link single-use and ties it to the person and the
  account they asked about.
  """

  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Users.User

  # Long enough to justify access at ops, short enough that an abandoned request
  # is not a lingering key.
  @ttl_seconds 1800

  schema "mcp_grant_requests" do
    field :server_name, :string
    field :account_handle, :string
    field :expires_at, :utc_datetime

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def changeset(request, attrs) do
    request
    |> cast(attrs, [:server_name, :account_handle, :expires_at])
    |> validate_required([:user_id, :server_name, :account_handle, :expires_at])
  end

  def ttl_seconds, do: @ttl_seconds

  def expires_at do
    DateTime.utc_now() |> DateTime.add(@ttl_seconds, :second) |> DateTime.truncate(:second)
  end

  def active?(%__MODULE__{expires_at: expires_at}) when not is_nil(expires_at),
    do: DateTime.after?(expires_at, DateTime.utc_now())

  def active?(_request), do: false
end
