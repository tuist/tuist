defmodule Tuist.Webhooks.WebhookEndpoint do
  @moduledoc """
  An account-scoped HTTPS destination that subscribes to one or more Tuist
  event types.

  When an event fires (e.g. a test case is muted), `Tuist.Webhooks.Dispatcher`
  looks up every endpoint in the account whose `event_types` includes that
  event and enqueues a delivery worker. `signing_secret` is Cloak-encrypted
  at rest via `Tuist.Vault.Binary`; reading the field transparently decrypts
  it for the delivery worker.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account

  @supported_event_types ~w(test_case.updated automation.triggered)

  @doc """
  Event types an endpoint can subscribe to. Used by the schema validator
  and the LiveView form's checkbox list, so adding a new event here is
  enough to expose it in both layers.
  """
  def supported_event_types, do: @supported_event_types

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "webhook_endpoints" do
    field :name, :string
    field :url, :string
    field :signing_secret, Tuist.Vault.Binary
    field :event_types, {:array, :string}, default: []

    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end

  def create_changeset(endpoint, attrs) do
    endpoint
    |> cast(attrs, [:account_id, :name, :url, :signing_secret, :event_types])
    |> validate_required([:account_id, :name, :url, :signing_secret])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_https_url()
    |> validate_event_types()
  end

  def update_changeset(endpoint, attrs) do
    endpoint
    |> cast(attrs, [:name, :url, :event_types])
    |> validate_required([:name, :url])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_https_url()
    |> validate_event_types()
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

  defp validate_event_types(changeset) do
    case get_field(changeset, :event_types) do
      [] ->
        add_error(changeset, :event_types, "must subscribe to at least one event")

      types when is_list(types) ->
        if Enum.all?(types, &(&1 in @supported_event_types)) do
          changeset
        else
          add_error(changeset, :event_types, "contains an unsupported event type")
        end

      _ ->
        add_error(changeset, :event_types, "must be a list")
    end
  end
end
