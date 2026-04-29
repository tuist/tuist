defmodule Tuist.Authentication do
  @moduledoc ~S"""
  A module to deal with authentication in the system.
  """
  alias Tuist.Accounts
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.Projects

  def authenticated_subject(token) do
    case Tuist.Guardian.resource_from_token(token) do
      {:ok, %AuthenticatedAccount{} = resource, _opts} ->
        resource

      {:ok, resource, _opts} ->
        resource |> Tuist.Repo.preload(:account) |> reject_if_inactive_user()

      _ ->
        user = Accounts.get_user_by_token(token)

        if is_nil(user) do
          account_or_project_token(token)
        else
          reject_if_inactive_user(user)
        end
    end
  end

  defp reject_if_inactive_user(%User{active: false}), do: nil
  defp reject_if_inactive_user(other), do: other

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
    with {:ok, resource, old_claims} <- Tuist.Guardian.resource_from_token(old_token, %{}, opts),
         {:ok, {:resource, resource}} when resource != nil <-
           {:ok, {:resource, preload_account(resource)}},
         {preferred_username, subject} <- refresh_subject(resource),
         new_claims =
           old_claims
           |> Map.drop(["jti", "iss", "iat", "nbf", "exp"])
           |> Map.put("preferred_username", preferred_username),
         {:ok, new_token, new_claims} <- __MODULE__.encode_and_sign(subject, new_claims, opts) do
      Tuist.Guardian.on_revoke(old_claims, old_token)
      {:ok, {old_token, old_claims}, {new_token, new_claims}}
    else
      {:error, reason} ->
        {:error, reason}

      {:ok, {:resource, nil}} ->
        {:error, "The token user doesn't exist"}
    end
  end

  defp preload_account(%User{} = user), do: Tuist.Repo.preload(user, :account)
  defp preload_account(%AuthenticatedAccount{} = resource), do: resource
  defp preload_account(_), do: nil

  defp refresh_subject(%User{account: %{name: name}} = user), do: {name, user}

  defp refresh_subject(%AuthenticatedAccount{account: %{name: name} = account}), do: {name, account}

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
