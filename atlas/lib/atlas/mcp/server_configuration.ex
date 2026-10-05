defmodule Atlas.MCP.ServerConfiguration do
  use Atlas.Schema

  import Ecto.Changeset

  schema "mcp_server_configurations" do
    field :name, :string
    field :url, :string
    field :auth_type, :string, default: "oauth2"
    field :authorization_url, :string
    field :token_url, :string
    field :registration_url, :string
    field :scopes, {:array, :string}, default: []
    field :scope_list, :string, virtual: true
    field :read_only, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  def changeset(server, attrs) do
    server
    |> cast(attrs, [:name, :url, :authorization_url, :token_url, :registration_url, :scope_list])
    |> put_scopes()
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name, :url, :auth_type])
    |> validate_format(:name, ~r/^[a-z][a-z0-9_-]*$/)
    |> validate_length(:name, max: 64)
    |> validate_url(:url)
    |> validate_oauth_urls()
    |> unique_constraint(:name)
  end

  defp put_scopes(changeset) do
    case fetch_change(changeset, :scope_list) do
      {:ok, value} -> put_change(changeset, :scopes, String.split(value || "", ~r/\s+/, trim: true))
      :error -> changeset
    end
  end

  defp validate_oauth_urls(changeset) do
    if get_field(changeset, :auth_type) == "oauth2" do
      changeset
      |> validate_required([:authorization_url, :token_url])
      |> validate_url(:authorization_url)
      |> validate_url(:token_url)
      |> validate_optional_url(:registration_url)
    else
      changeset
    end
  end

  defp validate_optional_url(changeset, field) do
    if get_field(changeset, field) in [nil, ""], do: changeset, else: validate_url(changeset, field)
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      uri = URI.parse(value)

      if uri.scheme == "https" and is_binary(uri.host) and String.contains?(uri.host, ".") and
           uri.userinfo == nil and uri.fragment == nil and public_hostname?(uri.host) do
        []
      else
        [{field, "must be a public HTTPS URL"}]
      end
    end)
  end

  defp public_hostname?(host) do
    hostname = String.downcase(host)

    not String.ends_with?(hostname, [".local", ".localhost", ".internal", ".test", ".invalid"]) and
      hostname != "localhost" and match?({:error, _}, :inet.parse_address(String.to_charlist(hostname)))
  end
end
