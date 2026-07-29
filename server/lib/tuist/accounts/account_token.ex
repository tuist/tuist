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

  @ci_scope "ci"
  @mcp_scope "mcp"
  @scim_scope "account:scim:write"

  @preset_scopes [@ci_scope, @mcp_scope]

  @scope_groups %{
    @ci_scope => [
      "account:cache:write",
      "project:cache:write",
      "project:previews:write",
      "project:bundles:write",
      "project:tests:write",
      "project:builds:write",
      "project:runs:write"
    ],
    @mcp_scope => [
      "project:admin:read",
      "project:cache:read",
      "project:previews:read",
      "project:bundles:read",
      "project:tests:read",
      "project:builds:read",
      "project:runs:read"
    ]
  }

  @fine_grained_scopes [
    @scim_scope,
    "account:cache:read",
    "account:cache:write",
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

  @valid_scopes @preset_scopes ++ @fine_grained_scopes
  @user_creatable_scopes @valid_scopes -- [@mcp_scope, @scim_scope]

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
    field :last_used_at, :utc_datetime
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

  def user_creatable_scopes, do: @user_creatable_scopes

  def preset_scope?(scope), do: scope in @preset_scopes

  def ci_scope, do: @ci_scope

  def scim_scope, do: @scim_scope

  def expand_scopes(scopes) do
    Enum.flat_map(scopes, fn scope ->
      Map.get(@scope_groups, scope, [scope])
    end)
  end

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

  def scim_changeset(attrs) do
    scim_changeset(%__MODULE__{}, attrs)
  end

  def scim_changeset(token, attrs) do
    token
    |> cast(attrs, [
      :account_id,
      :encrypted_token_hash,
      :scopes,
      :name,
      :all_projects
    ])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:account_id, :encrypted_token_hash, :scopes, :name])
    |> validate_length(:name, min: 1, max: 64)
    |> validate_format(:name, ~r/^[^\r\n]+$/, message: "must not contain line breaks")
    |> validate_scim_scope()
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

  defp validate_scim_scope(changeset) do
    validate_change(changeset, :scopes, fn :scopes, scopes ->
      if scopes == [@scim_scope] do
        []
      else
        [scopes: "must only contain #{@scim_scope}"]
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
