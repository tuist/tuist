defmodule Tuist.Authentication do
  @moduledoc ~S"""
  A module to deal with authentication in the system.
  """
  alias Tuist.Accounts
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Projects

  def authenticated_subject(token) do
    case Tuist.Guardian.resource_from_token(token) do
      {:ok, %AuthenticatedAccount{} = resource, _opts} ->
        resource

      {:ok, resource, _opts} ->
        Tuist.Repo.preload(resource, :account)

      _ ->
        user = Accounts.get_user_by_token(token)

        if is_nil(user) do
          account_or_project_token(token)
        else
          user
        end
    end
  end

  defp account_or_project_token(token) do
    project_token = Projects.get_project_by_full_token(token)

    if is_nil(project_token) do
      case Accounts.account_token(token, preload: [:account, :account_token_projects]) do
        {:ok, account_token} ->
          %AuthenticatedAccount{
            account: account_token.account,
            scopes: account_token.scopes,
            all_projects: account_token.all_projects,
            project_ids: Enum.map(account_token.account_token_projects, & &1.project_id),
            token_id: account_token.id,
            created_by_account_id: account_token.created_by_account_id
          }

        _ ->
          nil
      end
    else
      project_token
    end
  end

  @doc """
    Refreshes a given token, updating the account handle in the `preferred_username` claim.

    This overrides the default `refresh/2` function in `Tuist.Guardian` in order to support us updating the handle. Guardian's `on_*` hooks
    only run _after_ a token has been refreshed, resulting in the need to override the `refresh/2` function to update the handle _before_ a
    new token is signed.

    This follows the same functionality as the `refresh` function:
    1. Decode the old token to make sure it is valid.
    2. Drop the `jti`, `iss`, `iat`, `nbf`, and `exp` claims from the old token. [`Guardian.Token.Jwt.reset_claims/3`]
    3. Sign a new token.
    4. Call `on_refresh`, which is a wrapper around `on_encode_and_sign` and `on_revoke` - the `on_revoke_and_sign` hook is automatically
       called by us calling `encode_and_sign` here, we are calling `on_revoke` manually.

  """
  def refresh(old_token, opts) do
    with {:ok, user, old_claims} <- Tuist.Guardian.resource_from_token(old_token, %{}, opts),
         {:ok, {:user, user}} when user != nil <-
           {:ok, {:user, Tuist.Repo.preload(user, :account)}},
         preferred_username = user.account.name,
         new_claims =
           old_claims
           |> Map.drop(["jti", "iss", "iat", "nbf", "exp"])
           |> Map.put("preferred_username", preferred_username),
         {:ok, new_token, new_claims} <- __MODULE__.encode_and_sign(user, new_claims, opts) do
      Tuist.Guardian.on_revoke(old_claims, old_token)
      {:ok, {old_token, old_claims}, {new_token, new_claims}}
    else
      {:error, reason} ->
        {:error, reason}

      {:ok, {:user, nil}} ->
        {:error, "The token user doesn't exist"}
    end
  end

  def exchange(old_token, from_type, to_type, options) do
    Tuist.Guardian.exchange(old_token, from_type, to_type, options)
  end

  def encode_and_sign(resource, claims \\ %{}, opts \\ []) do
    projects =
      resource
      |> Projects.list_accessible_projects(recent: 5)
      |> Enum.map(&"#{&1.account.name}/#{&1.name}")

    claims = Map.put(claims, "projects", projects)
    Tuist.Guardian.encode_and_sign(resource, claims, opts)
  end

  def revoke(token, opts \\ []) do
    Tuist.Guardian.revoke(token, opts)
  end

  def decode_and_verify(token, claims_to_check \\ %{}, opts \\ []) do
    Tuist.Guardian.decode_and_verify(token, claims_to_check, opts)
  end
end
