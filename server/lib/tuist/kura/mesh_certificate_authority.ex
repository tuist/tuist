defmodule Tuist.Kura.MeshCertificateAuthority do
  @moduledoc """
  Per-account certificate authority that anchors a customer's Kura mesh.

  Kura's peer mTLS verifier trusts any client certificate that chains to the CA
  configured on the node, with no identity check beyond the chain
  (`WebPkiClientVerifier`). The CA file is therefore the trust boundary, so each
  account gets its own CA: a node only admits peers whose certificate chains to
  the same per-account CA, which keeps one tenant's mesh from admitting another
  tenant's nodes.

  The CA private key is stored encrypted at rest via `Tuist.Vault.Binary`.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "kura_mesh_certificate_authorities" do
    field :certificate_pem, :string
    field :encrypted_private_key, Tuist.Vault.Binary
    field :not_after, :utc_datetime

    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:account_id, :certificate_pem, :encrypted_private_key, :not_after])
    |> validate_required([:account_id, :certificate_pem, :encrypted_private_key, :not_after])
    |> foreign_key_constraint(:account_id)
    |> unique_constraint(:account_id)
  end
end
