defmodule TuistWeb.SlackOAuthController do
  @moduledoc """
  Controller for handling Slack OAuth flow.
  """

  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.Slack
  alias Tuist.Slack.Client, as: SlackClient
  alias TuistWeb.Errors.BadRequestError

  def callback(conn, params) do
    with {:ok, code} <- extract_code(params),
         {:ok, account_id} <- extract_account_id(params),
         %Account{} = account <- Accounts.get_account_by_id(account_id, preload: [:slack_installation]),
         redirect_uri = slack_redirect_uri(),
         {:ok, token_data} <- SlackClient.exchange_code_for_token(code, redirect_uri),
         {:ok, _installation} <- create_or_update_installation(account, token_data) do
      redirect(conn, to: ~p"/#{account.name}/integrations")
    else
      {:error, :missing_code} ->
        raise BadRequestError, dgettext("dashboard", "Invalid Slack authorization. Please try again.")

      {:error, :missing_account_id} ->
        raise BadRequestError, dgettext("dashboard", "Invalid Slack authorization. Please try again.")

      {:error, :invalid_state_token} ->
        raise BadRequestError, dgettext("dashboard", "Invalid authorization request. Please try again.")

      {:error, reason} when is_binary(reason) ->
        raise BadRequestError, dgettext("dashboard", "Slack authorization failed: %{reason}", reason: reason)

      {:error, %Ecto.Changeset{}} ->
        raise BadRequestError, dgettext("dashboard", "Failed to save Slack installation. Please try again.")
    end
  end

  def install_url(account_id) do
    state_token = Slack.generate_state_token(account_id)
    client_id = Environment.slack_client_id()
    redirect_uri = slack_redirect_uri()

    scopes = "chat:write,chat:write.public,channels:read,groups:read"

    "https://slack.com/oauth/v2/authorize?" <>
      URI.encode_query(%{
        client_id: client_id,
        scope: scopes,
        redirect_uri: redirect_uri,
        state: state_token
      })
  end

  defp extract_code(%{"code" => code}) when is_binary(code) and code != "" do
    {:ok, code}
  end

  defp extract_code(_params), do: {:error, :missing_code}

  defp extract_account_id(%{"state" => state_token}) when is_binary(state_token) do
    case Slack.verify_state_token(state_token) do
      {:ok, account_id} -> {:ok, account_id}
      {:error, _reason} -> {:error, :invalid_state_token}
    end
  end

  defp extract_account_id(_params), do: {:error, :missing_account_id}

  defp create_or_update_installation(account, token_data) do
    attrs = %{
      account_id: account.id,
      team_id: token_data.team_id,
      team_name: token_data.team_name,
      access_token: token_data.access_token,
      bot_user_id: token_data.bot_user_id
    }

    case account.slack_installation do
      nil -> Slack.create_installation(attrs)
      installation -> Slack.update_installation(installation, attrs)
    end
  end

  defp slack_redirect_uri do
    base_url = Environment.slack_redirect_base_url() || TuistWeb.Endpoint.url()
    base_url <> "/integrations/slack/callback"
  end
end
