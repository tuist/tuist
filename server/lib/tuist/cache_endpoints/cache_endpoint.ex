defmodule Tuist.CacheEndpoints.CacheEndpoint do
  @moduledoc """
  Schema for global Tuist-hosted cache endpoints.
  These are the cache nodes that serve binary caching for all Tuist-hosted users.
  Individual nodes can be disabled to take them out of rotation.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "cache_endpoints" do
    field :url, :string
    field :display_name, :string
    field :enabled, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  def changeset(endpoint \\ %__MODULE__{}, attrs) do
    endpoint
    |> cast(attrs, [:url, :display_name, :enabled])
    |> validate_required([:url, :display_name])
    |> validate_url(:url)
    |> unique_constraint([:url])
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn _, url ->
      case URI.parse(url) do
        %URI{scheme: scheme, host: host}
        when scheme in ["http", "https"] and is_binary(host) and host != "" ->
          []

        _ ->
          [{field, "must be a valid HTTP or HTTPS URL"}]
      end
    end)
  end
end
