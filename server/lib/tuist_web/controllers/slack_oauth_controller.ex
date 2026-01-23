defmodule TuistWeb.SlackOAuthController do
  @moduledoc """
  Controller for handling Slack OAuth flow.

  Supports two OAuth flows:
  - Account installation: Installs the Slack app to a workspace
  - Channel selection: Selects a channel for project reports via incoming-webhook
  """

  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Alerts
  alias Tuist.Environment
  alias Tuist.Projects
  alias Tuist.Projects.Project
  alias Tuist.Slack
  alias Tuist.Slack.Client, as: SlackClient
  alias TuistWeb.Errors.BadRequestError

  @account_slack_scopes "chat:write,chat:write.public"
  @channel_selection_scopes "incoming-webhook"

  def callback(conn, %{"error" => "access_denied", "state" => state_token}) do
    case Slack.verify_state_token(state_token) do
      {:ok, payload} ->
        handle_access_denied(conn, payload)

      {:error, reason} ->
        raise_state_token_error(reason)
    end
  end

  def callback(conn, %{"code" => code, "state" => state_token})
      when is_binary(code) and code != "" and is_binary(state_token) do
    case Slack.verify_state_token(state_token) do
      {:ok, payload} ->
        handle_verified_callback(conn, code, payload)

      {:error, reason} ->
        raise_state_token_error(reason)
    end
  end

  def callback(_conn, _params) do
    raise BadRequestError,
          dgettext("dashboard_slack", "Invalid Slack authorization. Please try again.")
  end

  defp handle_access_denied(conn, %{type: type})
       when type in [:alert_channel_selection, :flaky_alert_channel_selection] do
    render_popup_close(conn, nil, nil)
  end

  defp handle_access_denied(conn, %{type: :channel_selection, account_id: account_id, project_id: project_id}) do
    redirect_after_channel_cancel(conn, account_id, project_id)
  end

  defp handle_access_denied(conn, %{type: :account_installation, account_id: account_id}) do
    redirect_after_account_cancel(conn, account_id)
  end

  defp handle_access_denied(conn, account_id) when is_integer(account_id) do
    redirect_after_account_cancel(conn, account_id)
  end

  defp handle_verified_callback(conn, code, %{type: :alert_channel_selection} = payload) do
    handle_alert_channel_selection(conn, code, payload)
  end

  defp handle_verified_callback(conn, code, %{type: :flaky_alert_channel_selection}) do
    handle_flaky_alert_channel_selection(conn, code)
  end

  defp handle_verified_callback(conn, code, %{type: :channel_selection}) do
    handle_channel_selection(conn, code)
  end

  defp handle_verified_callback(conn, code, %{type: :account_installation, account_id: account_id}) do
    handle_account_installation(conn, code, account_id)
  end

  defp handle_verified_callback(conn, code, account_id) when is_integer(account_id) do
    handle_account_installation(conn, code, account_id)
  end

  defp raise_state_token_error(:expired) do
    raise BadRequestError,
          dgettext(
            "dashboard_slack",
            "Authorization request expired. Please start the Slack connection process again."
          )
  end

  defp raise_state_token_error(:invalid) do
    raise BadRequestError,
          dgettext("dashboard_slack", "Invalid authorization request. Please try again.")
  end

  def install_url(account_id) do
    state_token = Slack.generate_state_token(account_id)
    build_oauth_url(state_token, @account_slack_scopes)
  end

  def channel_selection_url(project_id, account_id) do
    state_token = Slack.generate_channel_selection_token(project_id, account_id)
    build_oauth_url(state_token, @channel_selection_scopes)
  end

  def alert_channel_selection_url(account_id, opts \\ []) do
    state_token = Slack.generate_alert_channel_selection_token(account_id, opts)
    build_oauth_url(state_token, @channel_selection_scopes)
  end

  def flaky_alert_channel_selection_url(project_id, account_id) do
    state_token = Slack.generate_flaky_alert_channel_selection_token(project_id, account_id)
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

  defp handle_channel_selection(conn, code) do
    case SlackClient.exchange_code_for_token(code, slack_redirect_uri()) do
      {:ok, token_data} ->
        incoming_webhook = token_data.incoming_webhook
        channel_id = incoming_webhook.channel_id
        channel_name = String.trim_leading(incoming_webhook.channel, "#")
        render_popup_close(conn, channel_id, channel_name)

      {:error, reason} when is_binary(reason) ->
        raise BadRequestError,
              dgettext("dashboard_slack", "Slack authorization failed: %{reason}", reason: reason)
    end
  end

  defp handle_alert_channel_selection(conn, code, %{alert_rule_id: alert_rule_id} = payload) do
    with {:ok, _account} <- Accounts.get_account_by_id(payload.account_id),
         {:ok, alert_rule} <- Alerts.get_alert_rule(alert_rule_id),
         {:ok, token_data} <- SlackClient.exchange_code_for_token(code, slack_redirect_uri()),
         {:ok, _alert_rule} <- update_alert_rule_channel(alert_rule, token_data) do
      render_popup_close(conn, nil, nil)
    else
      {:error, :not_found} ->
        raise BadRequestError, dgettext("dashboard_slack", "Alert rule not found. Please try again.")

      {:error, reason} when is_binary(reason) ->
        raise BadRequestError,
              dgettext("dashboard_slack", "Slack authorization failed: %{reason}", reason: reason)

      {:error, %Ecto.Changeset{}} ->
        raise BadRequestError,
              dgettext("dashboard_slack", "Failed to save channel selection. Please try again.")
    end
  end

  defp handle_alert_channel_selection(conn, code, _payload) do
    case SlackClient.exchange_code_for_token(code, slack_redirect_uri()) do
      {:ok, token_data} ->
        incoming_webhook = token_data.incoming_webhook
        channel_id = incoming_webhook.channel_id
        channel_name = String.trim_leading(incoming_webhook.channel, "#")
        render_popup_close(conn, channel_id, channel_name)

      {:error, reason} when is_binary(reason) ->
        raise BadRequestError,
              dgettext("dashboard_slack", "Slack authorization failed: %{reason}", reason: reason)
    end
  end

  defp handle_flaky_alert_channel_selection(conn, code) do
    case SlackClient.exchange_code_for_token(code, slack_redirect_uri()) do
      {:ok, token_data} ->
        incoming_webhook = token_data.incoming_webhook
        channel_id = incoming_webhook.channel_id
        channel_name = String.trim_leading(incoming_webhook.channel, "#")
        render_popup_close(conn, channel_id, channel_name)

      {:error, reason} when is_binary(reason) ->
        raise BadRequestError,
              dgettext("dashboard_slack", "Slack authorization failed: %{reason}", reason: reason)
    end
  end

  defp update_alert_rule_channel(alert_rule, token_data) do
    incoming_webhook = token_data.incoming_webhook
    channel_name = String.trim_leading(incoming_webhook.channel, "#")

    Alerts.update_alert_rule(alert_rule, %{
      slack_channel_id: incoming_webhook.channel_id,
      slack_channel_name: channel_name
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

  defp render_popup_close(conn, channel_id, channel_name) do
    conn
    |> put_view(TuistWeb.SlackOAuthHTML)
    |> put_layout(false)
    |> render("popup_close.html", channel_id: channel_id, channel_name: channel_name)
  end
end
