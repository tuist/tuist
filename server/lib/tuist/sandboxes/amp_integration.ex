defmodule Tuist.Sandboxes.AmpIntegration do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Vault.Binary

  @primary_key {:id, :binary_id, autogenerate: true}
  @derive {Inspect, except: [:provider_token, :token_fingerprint]}
  schema "amp_integrations" do
    belongs_to :account, Account
    field :provider_token, Binary, redact: true
    field :token_fingerprint, :string, redact: true
    field :enabled, :boolean, default: true
    field :revision, :integer, default: 1

    field :status, Ecto.Enum,
      values: [:pending, :running, :error, :disconnecting, :disconnected, :suspended],
      default: :pending

    field :last_checked_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  def changeset(integration, token) do
    integration
    |> cast(%{provider_token: String.trim(token)}, [:provider_token])
    |> validate_required([:provider_token])
    |> validate_length(:provider_token, max: 4096)
    |> validate_format(:provider_token, ~r/^aop_live_[A-Za-z0-9_-]+$/)
    |> put_fingerprint()
    |> put_change(:enabled, true)
    |> put_change(:status, :pending)
    |> put_change(:revision, integration.revision + 1)
    |> unique_constraint(:account_id)
    |> unique_constraint(:token_fingerprint)
  end

  defp put_fingerprint(changeset) do
    case get_field(changeset, :provider_token) do
      token when is_binary(token) ->
        put_change(changeset, :token_fingerprint, Base.encode16(:crypto.hash(:sha256, token)))

      _ ->
        changeset
    end
  end
end
