defmodule Tuist.Orchard.ServiceAccount do
  @moduledoc """
  Bearer-token identity for Orchard API clients.

  HTTP Basic auth maps `name` to one of these rows; the password is
  compared (constant-time) against `token_hash`. Roles control which
  endpoints the account can hit — same enum as upstream Orchard:

    * `compute:read` — list/get VMs and workers
    * `compute:write` — create/update/delete VMs and workers
    * `compute:connect` — open RPC channels (watch, port-forward, exec)
    * `admin:read` — read service accounts and cluster settings
    * `admin:write` — create/update/delete service accounts
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @valid_roles ~w(compute:read compute:write compute:connect admin:read admin:write)

  schema "orchard_service_accounts" do
    field :name, :string
    field :token_hash, :string
    field :roles, {:array, :string}, default: []

    field :token, :string, virtual: true

    timestamps(type: :utc_datetime)
  end

  def changeset(account, attrs) do
    account
    |> cast(attrs, [:name, :token, :roles])
    |> validate_required([:name, :token, :roles])
    |> validate_format(:name, ~r/^[a-z0-9][a-z0-9-]*$/)
    |> validate_subset(:roles, @valid_roles)
    |> unique_constraint(:name)
    |> hash_token()
  end

  def valid_roles, do: @valid_roles

  defp hash_token(%{valid?: true, changes: %{token: token}} = changeset) do
    put_change(changeset, :token_hash, Bcrypt.hash_pwd_salt(token))
  end

  defp hash_token(changeset), do: changeset
end
