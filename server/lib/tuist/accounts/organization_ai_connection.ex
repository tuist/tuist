defmodule Tuist.Accounts.OrganizationAIConnection do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Organization
  alias Tuist.URL
  alias Tuist.Vault.Binary

  schema "organization_ai_connections" do
    belongs_to :organization, Organization
    field :name, :string
    field :base_url, :string
    field :api_key, Binary, redact: true
    # `api_key` connections call `base_url` with `api_key`. A `claude_linked_billing`
    # connection has neither: Tuist calls Anthropic as its operator account and
    # bills the organization's linked Claude organization (`ClaudeLinkedBilling`).
    field :kind, :string, default: "api_key"
    field :anthropic_connection_id, :string

    timestamps(type: :utc_datetime)
  end

  def linked_billing_changeset(connection, anthropic_connection_id) do
    change(connection,
      kind: "claude_linked_billing",
      name: "Claude Platform",
      anthropic_connection_id: anthropic_connection_id
    )
  end

  def changeset(connection, attrs) do
    connection
    |> cast(attrs, [:name, :base_url, :api_key])
    |> update_change(:name, &(&1 && String.trim(&1)))
    |> update_change(:base_url, &(&1 && &1 |> String.trim() |> String.trim_trailing("/")))
    |> preserve_blank_key()
    |> validate_required([:organization_id, :name, :base_url, :api_key])
    |> validate_length(:name, max: 100)
    |> validate_length(:base_url, max: 2048)
    |> validate_length(:api_key, max: 4096)
    |> validate_format(:api_key, ~r/\A[^\s\x00-\x1f\x7f]+\z/)
    |> validate_change(:base_url, fn :base_url, url ->
      case URI.new(url) do
        {:ok, %URI{scheme: "https", host: host, userinfo: nil, query: nil, fragment: nil, port: port}}
        when is_binary(host) and host != "" and port in 1..65_535 ->
          if URL.public_url?(url), do: [], else: [base_url: "must use a public HTTPS endpoint"]

        _ ->
          [base_url: "must use a public HTTPS endpoint without credentials, query parameters or fragments"]
      end
    end)
    |> require_key_for_endpoint_change(connection, attrs["api_key"])
  end

  # Never forward a saved credential to a newly configured destination.
  defp require_key_for_endpoint_change(changeset, connection, submitted_key) do
    key_entered? = is_binary(submitted_key) and String.trim(submitted_key) != ""

    if connection.id && get_change(changeset, :base_url) && !key_entered?,
      do: add_error(changeset, :api_key, "must be entered again when changing the API base URL"),
      else: changeset
  end

  # Rotation is independent of model configuration; forms never receive saved keys.
  defp preserve_blank_key(changeset) do
    key = get_change(changeset, :api_key)
    key = if key, do: String.trim(key)

    if key in [nil, ""],
      do: delete_change(changeset, :api_key),
      else: put_change(changeset, :api_key, key)
  end
end
