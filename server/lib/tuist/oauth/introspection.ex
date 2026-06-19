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
      subject -> active_response(subject)
    end
  end

  defp active_response(subject) do
    %{
      active: true,
      iss: issuer(),
      sub: subject_id(subject),
      principal_kind: principal_kind(subject),
      cache_grants: Cache.cache_grants(subject)
    }
    |> maybe_put(:scope, scope_string(subject))
    |> maybe_put(:username, username(subject))
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
