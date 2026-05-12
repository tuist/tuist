defmodule Tuist.Webhooks.WebhookEndpoint do
  @moduledoc """
  An account-scoped HTTPS destination that can receive Tuist event envelopes.

  The same endpoint can be referenced by any number of automation
  `send_webhook` actions inside projects belonging to the account, so the URL
  and signing secret are managed in one place. `signing_secret` is
  Cloak-encrypted at rest via `Tuist.Vault.Binary`; reading the field
  transparently decrypts it for the delivery worker.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "webhook_endpoints" do
    field :name, :string
    field :url, :string
    field :signing_secret, Tuist.Vault.Binary

    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end

  def create_changeset(endpoint, attrs) do
    endpoint
    |> cast(attrs, [:account_id, :name, :url, :signing_secret])
    |> validate_required([:account_id, :name, :url, :signing_secret])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_https_url()
  end

  def update_changeset(endpoint, attrs) do
    endpoint
    |> cast(attrs, [:name, :url])
    |> validate_required([:name, :url])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_https_url()
  end

  def rotate_secret_changeset(endpoint, secret) when is_binary(secret) do
    change(endpoint, %{signing_secret: secret})
  end

  defp validate_https_url(changeset) do
    validate_change(changeset, :url, fn :url, url ->
      case URI.parse(url) do
        %URI{scheme: "https", host: host} when is_binary(host) and host != "" -> []
        _ -> [url: "must be a valid HTTPS URL"]
      end
    end)
  end
end
