defmodule Tuist.Kura.SelfHostedClient do
  @moduledoc """
  Tenant-scoped credential a customer uses to run self-hosted Kura nodes.

  A self-hosted node presents `client_id` + `client_secret` when it calls the
  control plane (token introspection and usage ingestion). The control plane
  authorizes the call against the owning account and constrains every response
  to that account's tenant, so a customer's node can never introspect tokens or
  report usage for another tenant.

  Only the Bcrypt hash of the secret is persisted; the plaintext secret is
  shown once at creation, mirroring `Tuist.Accounts.AccountToken`.
  `secret_last_four` keeps the trailing four characters so the dashboard can
  render a masked preview, the same hint webhook signing secrets expose.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "kura_self_hosted_clients" do
    field :client_id, :string
    field :encrypted_secret_hash, :string
    field :secret_last_four, :string
    field :name, :string
    field :last_used_at, :utc_datetime

    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:account_id, :client_id, :encrypted_secret_hash, :secret_last_four, :name])
    |> validate_required([:account_id, :client_id, :encrypted_secret_hash, :secret_last_four, :name])
    |> validate_name()
    |> foreign_key_constraint(:account_id)
    |> unique_constraint(:client_id)
    |> unique_constraint([:account_id, :name], message: "has already been taken")
  end

  @doc "The trailing four characters of `secret`, persisted as a masked-preview hint."
  def last_four(secret) when is_binary(secret), do: String.slice(secret, -4, 4)

  defp validate_name(changeset) do
    changeset
    |> update_change(:name, &String.trim/1)
    |> validate_length(:name, min: 1, max: 64)
    |> validate_format(:name, ~r/^[^\r\n]+$/, message: "must not contain line breaks")
  end
end
