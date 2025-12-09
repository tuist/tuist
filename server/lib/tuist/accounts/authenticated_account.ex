defmodule Tuist.Accounts.AuthenticatedAccount do
  @moduledoc """
  This module defines an authenticated account from an account token.

  Fields:
  - `account` - The account that owns the token
  - `scopes` - List of scope strings the token has access to
  - `all_projects` - When true, token has access to all projects under the account
  - `project_ids` - When all_projects is false, list of project IDs the token can access
  - `token_id` - The ID of the token used for authentication
  - `created_by_account_id` - The ID of the account that created this token
  """
  @enforce_keys [:account, :scopes]
  defstruct [:account, :scopes, :all_projects, :project_ids, :token_id, :created_by_account_id]
end
