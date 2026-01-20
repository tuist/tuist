defmodule Tuist.Guardian do
  @moduledoc """
  Module for Guardian callbacks.
  """

  use Guardian, otp_app: :tuist

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.Projects.Project

  def subject_for_token(%User{id: id}, _claims) do
    sub = to_string(id)
    {:ok, sub}
  end

  def subject_for_token(%Project{id: id}, _claims) do
    sub = to_string(id)
    {:ok, sub}
  end

  def subject_for_token(%Account{id: id}, _claims) do
    sub = to_string(id)
    {:ok, sub}
  end

  def subject_for_token(_, _) do
    {:error, :invalid_subject}
  end

  def resource_from_claims(%{"sub" => id, "type" => "account"} = claims) do
    case Accounts.get_account_by_id(id) do
      {:ok, account} ->
        {:ok,
         %AuthenticatedAccount{
           account: account,
           scopes: claims["scopes"],
           all_projects: false,
           project_ids: extract_project_ids(claims)
         }}

      {:error, :not_found} ->
        {:error, :resource_not_found}
    end
  end

  def resource_from_claims(%{"sub" => id}) do
    resource = Accounts.get_user_by_id(id)
    {:ok, resource}
  end

  defp extract_project_ids(%{"project_ids" => project_ids}) when is_list(project_ids), do: project_ids
  defp extract_project_ids(%{"project_id" => project_id}) when not is_nil(project_id), do: [project_id]
  defp extract_project_ids(_), do: nil

  def after_encode_and_sign(resource, claims, token, _options) do
    with {:ok, _} <-
           Guardian.DB.after_encode_and_sign(
             resource,
             claims["typ"],
             claims,
             Bcrypt.hash_pwd_salt(token <> Tuist.Environment.secret_key_password())
           ) do
      {:ok, token}
    end
  end

  def on_verify(claims, token, _options) do
    with {:ok, _} <- Guardian.DB.on_verify(claims, token) do
      {:ok, claims}
    end
  end

  def on_refresh({old_token, old_claims}, {new_token, new_claims}, _options) do
    with {:ok, _, _} <-
           Guardian.DB.on_refresh(
             {old_token, old_claims},
             {Bcrypt.hash_pwd_salt(new_token <> Tuist.Environment.secret_key_password()), new_claims}
           ) do
      {:ok, {old_token, old_claims}, {new_token, new_claims}}
    end
  end

  def on_revoke(claims, token, _options \\ []) do
    with {:ok, _} <- Guardian.DB.on_revoke(claims, token) do
      {:ok, claims}
    end
  end
end
