defmodule TuistWeb.SlackOAuthController do
  @moduledoc """
  Controller for handling Slack OAuth flow.
  """

  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.Slack
  alias Tuist.Slack.Client, as: SlackClient
  alias TuistWeb.Errors.BadRequestError

  @slack_scopes "chat:write,chat:write.public,channels:read,groups:read"

  def callback(conn, %{"code" => code, "state" => state_token})
      when is_binary(code) and code != "" and is_binary(state_token) do
    with {:ok, account_id} <- verify_state_token(state_token),
         {:ok, account} <- Accounts.get_account_by_id(account_id),
         {:ok, token_data} <- SlackClient.exchange_code_for_token(code, slack_redirect_uri()),
         {:ok, _installation} <- create_installation(account, token_data) do
      redirect(conn, to: ~p"/#{account.name}/integrations")
    else
      {:error, :invalid_state_token} ->
        raise BadRequestError, dgettext("dashboard", "Invalid authorization request. Please try again.")

      {:error, :not_found} ->
        raise BadRequestError, dgettext("dashboard", "Account not found. Please try again.")

      {:error, reason} when is_binary(reason) ->
        raise BadRequestError, dgettext("dashboard", "Slack authorization failed: %{reason}", reason: reason)

      {:error, %Ecto.Changeset{}} ->
        raise BadRequestError, dgettext("dashboard", "Failed to save Slack installation. Please try again.")
    end
  end

  def callback(_conn, _params) do
    raise BadRequestError, dgettext("dashboard", "Invalid Slack authorization. Please try again.")
  end

  def install_url(account_id) do
    state_token = Slack.generate_state_token(account_id)
    client_id = Environment.slack_client_id()
    redirect_uri = slack_redirect_uri()

    "https://slack.com/oauth/v2/authorize?" <>
      URI.encode_query(%{
        client_id: client_id,
        scope: @slack_scopes,
        redirect_uri: redirect_uri,
        state: state_token
      })
  end

  defp verify_state_token(state_token) do
    case Slack.verify_state_token(state_token) do
      {:ok, account_id} -> {:ok, account_id}
      {:error, _reason} -> {:error, :invalid_state_token}
    end
  end

  defp create_installation(account, token_data) do
    Slack.create_installation(%{
      account_id: account.id,
      team_id: token_data.team_id,
      team_name: token_data.team_name,
      access_token: token_data.access_token,
      bot_user_id: token_data.bot_user_id
    })
  end

  defp slack_redirect_uri do
    Environment.app_url(path: "/integrations/slack/callback")
  end
end
