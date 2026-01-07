defmodule TuistWeb.SlackOAuthController do
  @moduledoc """
  Controller for handling Slack OAuth flow.

  Supports two OAuth flows:
  - Account installation: Installs the Slack app to a workspace
  - Channel selection: Selects a channel for project reports via incoming-webhook
  """

  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.Projects
  alias Tuist.Projects.Project
  alias Tuist.Slack
  alias Tuist.Slack.Client, as: SlackClient
  alias TuistWeb.Errors.BadRequestError

  @account_slack_scopes "chat:write,chat:write.public"
  @channel_selection_scopes "incoming-webhook"

  def callback(conn, %{"error" => "access_denied", "state" => state_token}) do
    case verify_state_token(state_token) do
      {:ok, %{type: :channel_selection, account_id: account_id, project_id: project_id}} ->
        redirect_after_channel_cancel(conn, account_id, project_id)

      {:ok, %{type: :account_installation, account_id: account_id}} ->
        redirect_after_account_cancel(conn, account_id)

      {:ok, account_id} when is_integer(account_id) ->
        redirect_after_account_cancel(conn, account_id)

      {:error, :invalid_state_token} ->
        raise BadRequestError,
              dgettext("dashboard_slack", "Invalid authorization request. Please try again.")
    end
  end

  def callback(conn, %{"code" => code, "state" => state_token})
      when is_binary(code) and code != "" and is_binary(state_token) do
    case verify_state_token(state_token) do
      {:ok, %{type: :channel_selection, account_id: account_id, project_id: project_id}} ->
        handle_channel_selection(conn, code, account_id, project_id)

      {:ok, %{type: :account_installation, account_id: account_id}} ->
        handle_account_installation(conn, code, account_id)

      {:ok, account_id} when is_integer(account_id) ->
        handle_account_installation(conn, code, account_id)

      {:error, :invalid_state_token} ->
        raise BadRequestError,
              dgettext("dashboard_slack", "Invalid authorization request. Please try again.")
    end
  end

  def callback(_conn, _params) do
    raise BadRequestError,
          dgettext("dashboard_slack", "Invalid Slack authorization. Please try again.")
  end

  def install_url(account_id) do
    state_token = Slack.generate_state_token(account_id)
    build_oauth_url(state_token, @account_slack_scopes)
  end

  def channel_selection_url(project_id, account_id) do
    state_token = Slack.generate_channel_selection_token(project_id, account_id)
    build_oauth_url(state_token, @channel_selection_scopes)
  end

  defp build_oauth_url(state_token, scopes) do
    client_id = Environment.slack_client_id()
    redirect_uri = slack_redirect_uri()

    "https://slack.com/oauth/v2/authorize?" <>
      URI.encode_query(%{
        client_id: client_id,
        scope: scopes,
        redirect_uri: redirect_uri,
        state: state_token
      })
  end

  defp handle_account_installation(conn, code, account_id) do
    with {:ok, account} <- Accounts.get_account_by_id(account_id),
         {:ok, token_data} <- SlackClient.exchange_code_for_token(code, slack_redirect_uri()),
         {:ok, _installation} <- create_installation(account, token_data) do
      redirect(conn, to: ~p"/#{account.name}/integrations")
    else
      {:error, :not_found} ->
        raise BadRequestError, dgettext("dashboard_slack", "Account not found. Please try again.")

      {:error, reason} when is_binary(reason) ->
        raise BadRequestError,
              dgettext("dashboard_slack", "Slack authorization failed: %{reason}", reason: reason)

      {:error, %Ecto.Changeset{}} ->
        raise BadRequestError,
              dgettext("dashboard_slack", "Failed to save Slack installation. Please try again.")
    end
  end

  defp handle_channel_selection(conn, code, account_id, project_id) do
    with {:ok, account} <- Accounts.get_account_by_id(account_id),
         %Project{} = project <- Projects.get_project_by_id(project_id),
         {:ok, token_data} <- SlackClient.exchange_code_for_token(code, slack_redirect_uri()),
         {:ok, _project} <- update_project_channel(project, token_data) do
      redirect(conn, to: ~p"/#{account.name}/#{project.name}/settings")
    else
      nil ->
        raise BadRequestError, dgettext("dashboard_slack", "Project not found. Please try again.")

      {:error, :not_found} ->
        raise BadRequestError, dgettext("dashboard_slack", "Account not found. Please try again.")

      {:error, reason} when is_binary(reason) ->
        raise BadRequestError,
              dgettext("dashboard_slack", "Slack authorization failed: %{reason}", reason: reason)

      {:error, %Ecto.Changeset{}} ->
        raise BadRequestError,
              dgettext("dashboard_slack", "Failed to save channel selection. Please try again.")
    end
  end

  defp update_project_channel(project, token_data) do
    incoming_webhook = token_data.incoming_webhook

    Projects.update_project(project, %{
      slack_channel_id: incoming_webhook.channel_id,
      slack_channel_name: incoming_webhook.channel
    })
  end

  defp redirect_after_account_cancel(conn, account_id) do
    case Accounts.get_account_by_id(account_id) do
      {:ok, account} ->
        redirect(conn, to: ~p"/#{account.name}/integrations")

      {:error, :not_found} ->
        raise BadRequestError,
              dgettext("dashboard_slack", "Account not found. Please try again.")
    end
  end

  defp redirect_after_channel_cancel(conn, account_id, project_id) do
    with {:ok, account} <- Accounts.get_account_by_id(account_id),
         %Project{} = project <- Projects.get_project_by_id(project_id) do
      redirect(conn, to: ~p"/#{account.name}/#{project.name}/settings")
    else
      nil ->
        raise BadRequestError,
              dgettext("dashboard_slack", "Project not found. Please try again.")

      {:error, :not_found} ->
        raise BadRequestError,
              dgettext("dashboard_slack", "Account not found. Please try again.")
    end
  end

  defp verify_state_token(state_token) do
    case Slack.verify_state_token(state_token) do
      {:ok, payload} -> {:ok, payload}
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
    Environment.app_url(path: ~p"/integrations/slack/callback")
  end
end
