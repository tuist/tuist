defmodule TuistWeb.ClaudeLinkedBillingController do
  @moduledoc """
  Browser-bound linking of an organization's Claude Platform organization
  for billing (`Tuist.Accounts.ClaudeLinkedBilling`). The `state` and PKCE
  verifier stay in the session of the administrator who started linking,
  and expire with the ten-minute pushed authorization request.
  """
  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Accounts.OrganizationAI
  alias TuistWeb.Authentication
  alias TuistWeb.Errors.BadRequestError

  @session_key :claude_linked_billing

  def start(conn, %{"account_id" => account_id}) when is_binary(account_id) do
    user = Authentication.current_user(conn)

    with {account_id, ""} <- Integer.parse(account_id),
         {:ok, account} <- Accounts.get_account_by_id(account_id) do
      case OrganizationAI.start_claude_link(user, account) do
        {:ok, %{url: url, state: state, code_verifier: code_verifier}} ->
          conn
          |> put_session(@session_key, %{
            state: state,
            code_verifier: code_verifier,
            account_id: account.id,
            user_id: user.id,
            issued_at: System.system_time(:second)
          })
          |> redirect(external: url)

        {:error, :claude_unavailable} ->
          conn
          |> put_flash(:error, dgettext("dashboard_account", "Claude is unavailable right now. Try linking again later."))
          |> redirect(to: ai_path(account))

        {:error, _} ->
          invalid_request!()
      end
    else
      _ -> invalid_request!()
    end
  end

  def start(_conn, _params), do: invalid_request!()

  def callback(conn, %{"state" => state} = params) when is_binary(state) do
    user = Authentication.current_user(conn)

    with %{state: ^state, account_id: account_id, user_id: user_id, issued_at: issued_at} = pending <-
           get_session(conn, @session_key),
         true <- (System.system_time(:second) - issued_at) in -60..600,
         %{id: ^user_id} <- user,
         {:ok, account} <- Accounts.get_account_by_id(account_id) do
      conn = delete_session(conn, @session_key)

      conn =
        case complete(user, account, params, pending) do
          :ok -> put_flash(conn, :info, dgettext("dashboard_account", "Linked your Claude organization."))
          {:error, message} -> put_flash(conn, :error, message)
        end

      redirect(conn, to: ai_path(account))
    else
      _ -> invalid_request!()
    end
  end

  def callback(_conn, _params), do: invalid_request!()

  defp complete(user, account, %{"code" => code}, pending) when is_binary(code) do
    case OrganizationAI.link_claude(user, account, code, pending.code_verifier) do
      {:ok, _connection} ->
        :ok

      {:error, :already_linked} ->
        {:error, already_linked_message()}

      {:error, :claude_unavailable} ->
        {:error, failed_message()}

      {:error, _} ->
        {:error, dgettext("dashboard_account", "You no longer have permission to link a Claude organization.")}
    end
  end

  defp complete(_user, _account, %{"error" => "user_profile_already_linked"}, _pending),
    do: {:error, already_linked_message()}

  # The administrator cancelled or couldn't approve; nothing was linked.
  defp complete(_user, _account, _params, _pending), do: {:error, failed_message()}

  defp already_linked_message,
    do:
      dgettext(
        "dashboard_account",
        "That Claude organization is already linked to another Tuist organization. Unlink it there first."
      )

  defp failed_message,
    do:
      dgettext(
        "dashboard_account",
        "Your Claude organization wasn't linked. Linking needs an Admin or Billing role in a Claude organization that pays Anthropic directly."
      )

  defp ai_path(account), do: ~p"/#{account.name}/settings/ai/routing"

  defp invalid_request! do
    raise BadRequestError, dgettext("dashboard_account", "The Claude linking request is invalid or has expired.")
  end
end
