defmodule Atlas.MCP.OperatorGrant do
  @moduledoc """
  A short-lived operator grant for one upstream MCP server.

  Atlas stores the grant and forwards it; it never verifies it. The signature,
  issuer, audience, expiry and subject are checked by the upstream that minted
  the trust — Atlas holding the public key would only add a second place for
  that decision to drift. The claims read here are used to key, expire and
  display the grant, never to authorize anything.

  One grant per user per server: setting a new one replaces the old, because an
  investigation looks at one customer account at a time and a stored grant that
  nobody is using should not outlive the moment it was pasted.
  """

  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Encrypted.Binary
  alias Atlas.Users.User

  schema "mcp_operator_grants" do
    field :server_name, :string
    field :account_handle, :string
    field :token, Binary
    field :expires_at, :utc_datetime

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def changeset(grant, attrs) do
    grant
    |> cast(attrs, [:server_name, :account_handle, :token, :expires_at])
    |> validate_required([:user_id, :server_name, :account_handle, :token, :expires_at])
    |> unique_constraint([:user_id, :server_name])
  end

  @doc "Whether the grant is still within its expiry."
  def active?(%__MODULE__{expires_at: expires_at}) when not is_nil(expires_at) do
    DateTime.after?(expires_at, DateTime.utc_now())
  end

  def active?(_grant), do: false

  @doc """
  Reads `account_handle`, `tier` and `exp` out of a grant token's payload.

  Deliberately unverified — see the module note. A token whose payload cannot be
  read, or which is missing a claim, is rejected here so it cannot be stored in a
  shape the UI would misreport; that is a usability check, not a security one.

  `tier` is the exception: the upstream decides what a grant may do from it, so a
  tier this does not recognise is refused rather than carried along as an unknown
  value. Reading it wrong in the permissive direction would hand Atlas a grant it
  believes is read-only and the upstream believes is not.
  """
  def describe(token) when is_binary(token) do
    with [_header, payload, _signature] <- String.split(token, "."),
         {:ok, json} <- Base.url_decode64(payload, padding: false),
         {:ok, %{"account_handle" => handle, "exp" => exp} = claims} when is_binary(handle) and is_integer(exp) <-
           JSON.decode(json),
         {:ok, tier} <- fetch_tier(claims),
         {:ok, expires_at} <- DateTime.from_unix(exp) do
      {:ok, %{account_handle: handle, tier: tier, expires_at: DateTime.truncate(expires_at, :second)}}
    else
      _ -> {:error, :unreadable_grant}
    end
  end

  def describe(_token), do: {:error, :unreadable_grant}

  # Mirrors the upstream's own tier parsing: anything that is not one of the two
  # known tiers is not a grant Atlas can reason about.
  defp fetch_tier(%{"tier" => "read"}), do: {:ok, :read}
  defp fetch_tier(%{"tier" => "admin"}), do: {:ok, :admin}
  defp fetch_tier(_claims), do: :error
end
