defmodule Tuist.Accounts.AccountToken do
  @moduledoc """
  A module that represents fine-grained access tokens for accounts.

  Account tokens provide scoped API access with optional project restrictions
  and expiration dates.

  ## Scopes

  Scopes follow the format: `{entity_type}:{object}:{access_level}`

  Access levels:
  - `read` - Read-only access
  - `write` - Full access (read and write)

  Entity types:
  - `account:` - Account-level scopes (organization-wide)
  - `project:` - Project-level scopes (per-project)
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.AccountTokenProject

  @valid_scopes [
    "ci",
    "account:members:read",
    "account:members:write",
    "account:registry:read",
    "account:registry:write",
    "project:previews:read",
    "project:previews:write",
    "project:admin:read",
    "project:admin:write",
    "project:cache:read",
    "project:cache:write",
    "project:bundles:read",
    "project:bundles:write",
    "project:tests:read",
    "project:tests:write",
    "project:builds:read",
    "project:builds:write",
    "project:runs:read",
    "project:runs:write"
  ]

  @derive {
    Flop.Schema,
    filterable: [:account_id, :name, :all_projects], sortable: [:inserted_at, :expires_at, :name]
  }

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "account_tokens" do
    field :encrypted_token_hash, :string
    field :scopes, {:array, :string}
    field :name, :string
    field :expires_at, :utc_datetime
    field :all_projects, :boolean, default: false

    belongs_to :account, Account
    belongs_to :created_by_account, Account

    has_many :account_token_projects, AccountTokenProject
    has_many :projects, through: [:account_token_projects, :project]

    timestamps(type: :utc_datetime)
  end

  @doc """
  Returns all valid scopes for account tokens.
  """
  def valid_scopes, do: @valid_scopes

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :account_id,
      :created_by_account_id,
      :encrypted_token_hash,
      :scopes,
      :name,
      :expires_at,
      :all_projects
    ])
    |> validate_required([:account_id, :encrypted_token_hash, :scopes, :name])
    |> validate_name()
    |> validate_scopes()
    |> validate_expiration()
    |> unique_constraint([:account_id, :encrypted_token_hash])
    |> unique_constraint([:account_id, :name], name: "account_tokens_account_id_name_index")
  end

  defp validate_name(changeset) do
    changeset
    |> validate_format(:name, ~r/^[a-zA-Z0-9-_]+$/,
      message: "must contain only alphanumeric characters, hyphens, and underscores"
    )
    |> validate_length(:name, min: 1, max: 32)
    |> update_change(:name, &String.downcase/1)
  end

  defp validate_scopes(changeset) do
    validate_change(changeset, :scopes, fn :scopes, scopes ->
      invalid = Enum.reject(scopes, &(&1 in @valid_scopes))

      if Enum.empty?(invalid) do
        []
      else
        [scopes: "contains invalid scopes: #{Enum.join(invalid, ", ")}"]
      end
    end)
  end

  defp validate_expiration(changeset) do
    validate_change(changeset, :expires_at, fn :expires_at, expires_at ->
      if DateTime.after?(expires_at, DateTime.utc_now()) do
        []
      else
        [expires_at: "must be in the future"]
      end
    end)
  end
end
