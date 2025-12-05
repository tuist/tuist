defmodule Tuist.Accounts.Scopes do
  @moduledoc """
  Defines and validates access token scopes.

  Scopes follow the format: `{entity_type}:{object}:{access_level}`

  Access levels:
  - `read` - Read-only access
  - `write` - Full access (read and write)

  Entity types:
  - `account:` - Account-level scopes (organization-wide)
  - `project:` - Project-level scopes (per-project)
  """

  @account_scopes [
    "account:members:read",
    "account:members:write",
    "account:registry:read",
    "account:registry:write"
  ]

  @project_scopes [
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
    "project:builds:write"
  ]

  @all_scopes @account_scopes ++ @project_scopes

  @doc """
  Returns all valid scopes.
  """
  def all_scopes, do: @all_scopes

  @doc """
  Returns all account-level scopes.
  """
  def account_scopes, do: @account_scopes

  @doc """
  Returns all project-level scopes.
  """
  def project_scopes, do: @project_scopes

  @doc """
  Checks if a scope string is valid.
  """
  def valid?(scope), do: scope in @all_scopes

  @doc """
  Validates a list of scopes.

  Returns `:ok` if all scopes are valid,
  or `{:error, invalid_scopes}` with a list of invalid scopes.
  """
  def validate(scopes) when is_list(scopes) do
    invalid = Enum.reject(scopes, &valid?/1)
    if Enum.empty?(invalid), do: :ok, else: {:error, invalid}
  end

  @doc """
  Parses a scope string into its components.

  Returns `{:ok, %{entity_type: string, object: string, access_level: string}}` on success,
  or `{:error, :invalid_format}` if the scope doesn't match the expected format.
  """
  def parse(scope) when is_binary(scope) do
    case String.split(scope, ":") do
      [entity_type, object, access_level] ->
        {:ok, %{entity_type: entity_type, object: object, access_level: access_level}}

      _ ->
        {:error, :invalid_format}
    end
  end

  @doc """
  Checks if a scope is an account-level scope.
  """
  def account_scope?(scope), do: scope in @account_scopes

  @doc """
  Checks if a scope is a project-level scope.
  """
  def project_scope?(scope), do: scope in @project_scopes
end
