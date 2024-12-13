defmodule Tuist.Authentication do
  @moduledoc ~S"""
  A module to deal with authentication in the system.
  """
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Projects
  alias Tuist.Accounts

  def authenticated_subject(token) do
    case Tuist.Guardian.resource_from_token(token) do
      {:ok, resource, _opts} ->
        resource

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
      case Accounts.account_token(token, preload: [:account]) do
        {:ok, account_token} ->
          %AuthenticatedAccount{account: account_token.account, scopes: account_token.scopes}

        _ ->
          nil
      end
    else
      project_token
    end
  end

  def refresh(token, opts) do
    Tuist.Guardian.refresh(token, opts)
  end

  def exchange(old_token, from_type, to_type, options) do
    Tuist.Guardian.exchange(old_token, from_type, to_type, options)
  end

  def encode_and_sign(resource, claims \\ %{}, opts \\ []) do
    Tuist.Guardian.encode_and_sign(resource, claims, opts)
  end

  def revoke(token, opts \\ []) do
    Tuist.Guardian.revoke(token, opts)
  end

  def decode_and_verify(token, claims_to_check \\ %{}, opts \\ []) do
    Tuist.Guardian.decode_and_verify(token, claims_to_check, opts)
  end
end
