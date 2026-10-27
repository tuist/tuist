defmodule Tuist.Webhooks.WebhookEndpoint do
  @moduledoc """
  An account-scoped HTTPS destination that subscribes to one or more Tuist
  event types.

  When an event fires (e.g. a test case is muted), `Tuist.Webhooks.Dispatcher`
  looks up every endpoint in the account whose `event_types` includes that
  event and enqueues a delivery worker. `signing_secret` is Cloak-encrypted
  at rest via `Tuist.Vault.Binary`; reading the field transparently decrypts
  it for the delivery worker.

  `signing_secret_last_four` mirrors the last four characters of the
  plaintext secret in cleartext so the dashboard can render a masked
  preview (`tuist_webhook_••••…••••XYZ`) without invoking Cloak on every
  endpoint row. The tail is set whenever the secret is generated or
  rotated; the encrypted blob remains the source of truth for HMAC.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Vault.Binary

  @event_groups [
    %{
      key: "test_cases",
      label: "Test cases",
      events: [
        %{
          type: "test_case.created",
          description: "A test case was observed for the first time in this account."
        },
        %{
          type: "test_case.updated",
          description: "A test case's attributes changed."
        }
      ]
    },
    %{
      key: "previews",
      label: "Previews",
      events: [
        %{
          type: "preview.created",
          description: "A new preview was created in this account."
        },
        %{
          type: "preview.deleted",
          description: "A preview was deleted from this account."
        }
      ]
    }
  ]

  @supported_event_types Enum.flat_map(@event_groups, fn group ->
                           Enum.map(group.events, & &1.type)
                         end)

  @doc """
  Event types an endpoint can subscribe to. Used by the schema validator
  and (indirectly, via `event_groups/0`) by the LiveView form.
  """
  def supported_event_types, do: @supported_event_types

  @doc """
  Resource-grouped catalogue of subscribable events. The webhook modal
  renders one section per group with its events as checkbox items; adding
  an event here is enough to surface it in the form.
  """
  def event_groups, do: @event_groups

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "webhook_endpoints" do
    field :name, :string
    field :url, Binary
    field :signing_secret, Binary
    field :signing_secret_last_four, :string
    field :event_types, {:array, :string}, default: []

    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end

  def create_changeset(endpoint, attrs) do
    endpoint
    |> cast(attrs, [
      :account_id,
      :name,
      :url,
      :signing_secret,
      :signing_secret_last_four,
      :event_types
    ])
    |> validate_required([:account_id, :name, :url, :signing_secret, :signing_secret_last_four])
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
    change(endpoint, %{signing_secret: secret, signing_secret_last_four: last_four(secret)})
  end

  @doc """
  Returns the last four characters of `secret`, used as the cleartext
  mirror persisted alongside the Cloak-encrypted blob. Falls back to the
  whole secret for inputs shorter than the prefix it would normally
  carry — only ever happens in tests.
  """
  def last_four(secret) when is_binary(secret) do
    case String.length(secret) do
      n when n > 4 -> String.slice(secret, -4, 4)
      _ -> secret
    end
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
