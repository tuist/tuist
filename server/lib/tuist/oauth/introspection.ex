defmodule Tuist.OAuth.Introspection do
  @moduledoc false

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.Authentication
  alias Tuist.Cache
  alias Tuist.Projects.Project

  @cache_token_type "cache"

  @doc """
  Unconstrained introspection for the Tuist-operated control-plane client.

  Every managed cache node authenticates as that client, so the response is not
  narrowed to one tenant: it serves them all.
  """
  def token_response(token) do
    case Authentication.authenticated_subject(token) do
      nil -> cache_token_response(token)
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
        cache_token_response(token, account)

      subject ->
        grants = scope_grants_to_account(Cache.cache_grants(subject), account)

        if grants_present?(grants) do
          active_response(subject, grants)
        else
          %{active: false}
        end
    end
  end

  # A cache token cannot resolve to a subject. Guardian refuses it on purpose, so
  # that a token minted to reach the cache can never act as an API credential.
  # It carries the grants it was minted with, though, so it can be answered from
  # itself. Verifying it here keeps that refusal intact: nothing about this makes
  # a cache token resolvable anywhere else.
  #
  # This is the only way a node can be told what one of these tokens may reach.
  # A node holds no verification key of its own, and it should not: the key that
  # signs these also signs API credentials, so a node that could verify locally
  # would also be a node that could mint them. Without an answer here, a node
  # reports every exchanged token inactive and denies the request.
  defp cache_token_response(token) do
    case verified_cache_token(token) do
      {:ok, claims, grants} -> cache_token_active(claims, grants)
      :error -> %{active: false}
    end
  end

  defp cache_token_response(token, %Account{} = account) do
    with {:ok, claims, grants} <- verified_cache_token(token),
         scoped when scoped != :empty <- scoped_or_empty(grants, account) do
      cache_token_active(claims, scoped)
    else
      {:ok, claims, _grants} -> payment_required_or_inactive(claims, account)
      _ -> %{active: false}
    end
  end

  # A token whose grants went empty because the account exhausted its plan still
  # has something to say. Reporting it inactive would have the node answer 401,
  # losing the only thing that tells the caller what to do about it.
  defp payment_required_or_inactive(claims, %Account{name: name}) do
    handles = Map.get(claims, "cache_payment_required", [])
    handle = String.downcase(name)

    if Enum.any?(handles, &(String.downcase(&1) == handle)) do
      cache_token_active(claims, empty_grants())
    else
      %{active: false}
    end
  end

  defp empty_grants do
    %{"account" => %{"read" => [], "write" => []}, "project" => %{"read" => [], "write" => []}}
  end

  defp verified_cache_token(token) do
    case Tuist.Guardian.decode_and_verify(token, %{"typ" => @cache_token_type}) do
      {:ok, %{"cache_grants" => grants} = claims} -> {:ok, claims, grants}
      _ -> :error
    end
  end

  # `principal_kind` is omitted: the claims do not record what the token was
  # minted for, and a node treats its absence as an unnamed subject.
  defp cache_token_active(claims, grants) do
    %{
      active: true,
      iss: issuer(),
      sub: claims["sub"],
      cache_grants: grants,
      cache_payment_required: Map.get(claims, "cache_payment_required", [])
    }
  end

  defp scoped_or_empty(grants, account) do
    scoped = scope_grants_to_account(grants, account)
    if grants_present?(scoped), do: scoped, else: :empty
  end

  defp active_response(subject, grants) do
    %{
      active: true,
      iss: issuer(),
      sub: subject_id(subject),
      principal_kind: principal_kind(subject),
      cache_grants: grants,
      cache_payment_required: Cache.payment_required_handles(subject)
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
