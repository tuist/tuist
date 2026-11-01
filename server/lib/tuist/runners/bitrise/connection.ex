defmodule Tuist.Runners.Bitrise.Connection do
  @moduledoc """
  An account's link to one Bitrise workspace: the workspace slug and an
  encrypted API token that can list the workspace's builds.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Runners.Bitrise.Pool
  alias Tuist.Vault.Binary

  schema "runner_bitrise_connections" do
    field :workspace_slug, :string
    field :workspace_name, :string
    field :api_token, Binary, redact: true
    field :enabled, :boolean, default: true
    field :last_polled_at, :utc_datetime
    field :last_error, :string
    field :last_error_at, :utc_datetime

    belongs_to :account, Account
    has_many :pools, Pool

    timestamps(type: :utc_datetime)
  end

  def changeset(connection, attrs) do
    connection
    |> cast(attrs, [:account_id, :workspace_slug, :workspace_name, :api_token, :enabled])
    |> update_change(:workspace_slug, &String.trim/1)
    |> update_change(:api_token, &String.trim/1)
    |> validate_required([:account_id, :workspace_slug, :api_token])
    |> validate_format(:workspace_slug, ~r/\A[a-zA-Z0-9_-]+\z/)
    |> unique_constraint(:account_id)
  end
end
