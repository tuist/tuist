defmodule Tuist.OAuth.Introspection do
  @moduledoc false

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.Authentication
  alias Tuist.Cache
  alias Tuist.Projects.Project

  def token_response(token) do
    case Authentication.authenticated_subject(token) do
      nil -> %{active: false}
      subject -> active_response(subject, Cache.cache_grants(subject))
    end
  end

  @doc """
  Tenant-scoped introspection for self-hosted Kura nodes.

  The response is constrained to `account`: only grants for that account's own
  handle and its projects survive. A token with no grant touching the account
  is reported as inactive, so a customer's node cannot learn anything about, or
  serve, another tenant's tokens.
  """
  def token_response(token, %Account{} = account) do
    case Authentication.authenticated_subject(token) do
      nil ->
        %{active: false}

      subject ->
        grants = scope_grants_to_account(Cache.cache_grants(subject), account)

        if grants_present?(grants) do
          active_response(subject, grants)
        else
          %{active: false}
        end
    end
  end

  defp active_response(subject, grants) do
    %{
      active: true,
      iss: issuer(),
      sub: subject_id(subject),
      principal_kind: principal_kind(subject),
      cache_grants: grants
    }
    |> maybe_put(:scope, scope_string(subject))
    |> maybe_put(:username, username(subject))
  end

  defp scope_grants_to_account(%{"account" => account_bucket, "project" => project_bucket}, %Account{name: name}) do
    handle = String.downcase(name)
    project_prefix = handle <> "/"

    %{
      "account" => %{
        "read" => keep_matching(account_bucket["read"], &(String.downcase(&1) == handle)),
        "write" => keep_matching(account_bucket["write"], &(String.downcase(&1) == handle))
      },
      "project" => %{
        "read" => keep_matching(project_bucket["read"], &String.starts_with?(String.downcase(&1), project_prefix)),
        "write" => keep_matching(project_bucket["write"], &String.starts_with?(String.downcase(&1), project_prefix))
      }
    }
  end

  defp keep_matching(handles, predicate) when is_list(handles), do: Enum.filter(handles, predicate)
  defp keep_matching(_handles, _predicate), do: []

  defp grants_present?(%{"account" => account_bucket, "project" => project_bucket}) do
    account_bucket["read"] != [] or account_bucket["write"] != [] or
      project_bucket["read"] != [] or project_bucket["write"] != []
  end

  defp subject_id(%User{id: id}), do: to_string(id)
  defp subject_id(%AuthenticatedAccount{account: %Account{id: id}}), do: to_string(id)
  defp subject_id(%Account{id: id}), do: to_string(id)
  defp subject_id(%Project{id: id}), do: to_string(id)

  defp principal_kind(%User{}), do: "user"
  defp principal_kind(%AuthenticatedAccount{}), do: "account"
  defp principal_kind(%Account{}), do: "account"
  defp principal_kind(%Project{}), do: "project"

  defp username(%User{email: email}), do: email
  defp username(%AuthenticatedAccount{account: %Account{name: name}}), do: name
  defp username(%Account{name: name}), do: name

  defp username(%Project{account: %Account{name: account_name}, name: project_name}),
    do: "#{account_name}/#{project_name}"

  defp scope_string(%AuthenticatedAccount{scopes: scopes}) when is_list(scopes) do
    scope_string(scopes)
  end

  defp scope_string(scopes) when is_list(scopes) do
    scopes
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp scope_string(%Project{}), do: "project:cache:read project:cache:write"
  defp scope_string(_), do: nil

  defp issuer do
    :tuist
    |> Application.fetch_env!(Tuist.Guardian)
    |> Keyword.fetch!(:issuer)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
