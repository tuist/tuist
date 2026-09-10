defmodule Tuist.Runners.GitLab.Connection do
  @moduledoc "An encrypted GitLab runner credential bound to an account and GitLab instance."
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Vault.Binary

  schema "runner_gitlab_connections" do
    field :url, :string, default: "https://gitlab.com"
    field :runner_token, Binary, redact: true
    field :enabled, :boolean, default: true
    field :last_polled_at, :utc_datetime
    field :last_error, :string
    belongs_to :account, Account
    timestamps(type: :utc_datetime)
  end

  def changeset(connection, attrs) do
    connection
    |> cast(attrs, [:account_id, :url, :runner_token, :enabled])
    |> validate_required([:account_id, :url, :runner_token])
    |> update_change(:url, &String.trim_trailing(&1, "/"))
    |> validate_change(:url, fn :url, url ->
      case URI.parse(url) do
        %URI{scheme: "https", host: host, userinfo: nil, query: nil, fragment: nil} when is_binary(host) and host != "" ->
          []

        _ ->
          [url: "must be an HTTPS GitLab instance URL without credentials, query or fragment"]
      end
    end)
    |> validate_format(:runner_token, ~r/\Aglrt-/, message: "must be a runner authentication token (starts with glrt-)")
    |> unique_constraint([:account_id, :url])
  end
end
