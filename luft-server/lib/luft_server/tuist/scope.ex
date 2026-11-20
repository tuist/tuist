defmodule LuftServer.Tuist.Scope do
  @moduledoc "An authoritative, request-scoped projection of Tuist identity and membership."

  alias LuftServer.Config
  alias LuftServer.Sessions

  @enforce_keys [:user_id, :account_id, :organization_id, :people, :can_create_threads]
  defstruct [:user_id, :account_id, :organization_id, :people, :can_create_threads]

  def load(session, handle) when is_binary(handle) do
    with {:ok, token} <- Sessions.access_token(session),
         {:ok, response} <-
           Req.get(
             Config.tuist_issuer() <>
               "/api/accounts/" <>
               URI.encode(handle, &URI.char_unreserved?/1) <> "/luft-context",
             Keyword.merge(
               [auth: {:bearer, token}, redirect: false, retry: false, receive_timeout: 10_000],
               Config.req_options()
             )
           ) do
      decode(response, session.user_sub)
    else
      {:error, :reauthenticate} -> {:error, :unauthorized}
      _ -> {:error, :tuist_unavailable}
    end
  end

  defp decode(%{status: 200, body: body}, subject) do
    with %{
           "user_id" => user_id,
           "account_id" => account_id,
           "organization_id" => organization_id,
           "can_create_threads" => can_create_threads,
           "people" => people
         } <- body,
         true <- is_integer(user_id) and to_string(user_id) == subject,
         true <- is_integer(account_id),
         true <- is_nil(organization_id) or is_integer(organization_id),
         true <- is_boolean(can_create_threads) and is_list(people),
         true <- Enum.all?(people, &person?/1) do
      {:ok,
       %__MODULE__{
         user_id: user_id,
         account_id: account_id,
         organization_id: organization_id,
         can_create_threads: can_create_threads,
         people: Enum.map(people, &%{id: &1["id"], handle: &1["handle"], active: &1["active"]})
       }}
    else
      _ -> {:error, :tuist_unavailable}
    end
  end

  defp decode(%{status: 401}, _subject), do: {:error, :unauthorized}
  defp decode(%{status: status}, _subject) when status in [403, 404], do: {:error, :not_found}
  defp decode(_response, _subject), do: {:error, :tuist_unavailable}

  defp person?(%{"id" => id, "handle" => handle, "active" => active}),
    do: is_integer(id) and is_binary(handle) and is_boolean(active)

  defp person?(_person), do: false
end
