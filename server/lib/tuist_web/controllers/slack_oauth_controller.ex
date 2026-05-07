defmodule TuistWeb.SlackOAuthController do
  @moduledoc """
  Controller for handling the Slack OAuth flow.

  Tuist's integration for Slack only requests the `incoming-webhook` scope. Each
  destination (project report, alert rule, flaky test alert, automation action)
  goes through its own channel-selection OAuth flow that returns a single
  webhook URL bound to the channel the user picked.
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
    render_popup_close(conn, nil)
  end

  defp handle_access_denied(conn, %{type: :channel_selection, account_id: account_id, project_id: project_id}) do
    redirect_after_channel_cancel(conn, account_id, project_id)
  end

  defp handle_verified_callback(conn, code, %{type: :alert_channel_selection} = payload) do
    handle_alert_channel_selection(conn, code, payload)
  end

  defp handle_verified_callback(conn, code, %{type: :flaky_alert_channel_selection}) do
    handle_flaky_alert_channel_selection(conn, code)
  end

  defp handle_verified_callback(conn, code, %{type: :channel_selection} = payload) do
    handle_channel_selection(conn, code, payload)
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

  defp handle_channel_selection(conn, code, _payload) do
    render_channel_selection(conn, code)
  end

  defp handle_alert_channel_selection(conn, code, %{alert_rule_id: alert_rule_id} = payload) do
    with {:ok, _account} <- Accounts.get_account_by_id(payload.account_id),
         {:ok, alert_rule} <- Alerts.get_alert_rule(alert_rule_id),
         {:ok, token_data} <- SlackClient.exchange_code_for_token(code, slack_redirect_uri()),
         {:ok, _alert_rule} <- update_alert_rule_channel(alert_rule, token_data) do
      render_popup_close(conn, nil)
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
    render_channel_selection(conn, code)
  end

  defp handle_flaky_alert_channel_selection(conn, code) do
    render_channel_selection(conn, code)
  end

  defp render_channel_selection(conn, code) do
    case SlackClient.exchange_code_for_token(code, slack_redirect_uri()) do
      {:ok, %{incoming_webhook: %{channel_id: channel_id, channel: channel, url: webhook_url}}} ->
        channel_name = String.trim_leading(channel, "#")

        case Slack.sign_channel_result(%{
               channel_id: channel_id,
               channel_name: channel_name,
               webhook_url: webhook_url
             }) do
          {:ok, token} ->
            render_popup_close(conn, token)

          {:error, :invalid_webhook_url} ->
            raise BadRequestError,
                  dgettext(
                    "dashboard_slack",
                    "Slack returned an unexpected webhook URL. Please try again."
                  )
        end

      {:error, reason} when is_binary(reason) ->
        raise BadRequestError,
              dgettext("dashboard_slack", "Slack authorization failed: %{reason}", reason: reason)
    end
  end

  defp update_alert_rule_channel(alert_rule, %{
         incoming_webhook: %{channel_id: channel_id, channel: channel, url: webhook_url}
       }) do
    if Slack.slack_webhook_url?(webhook_url) do
      channel_name = String.trim_leading(channel, "#")

      Alerts.update_alert_rule(alert_rule, %{
        slack_channel_id: channel_id,
        slack_channel_name: channel_name,
        slack_webhook_url: webhook_url
      })
    else
      {:error, :invalid_webhook_url}
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

  defp slack_redirect_uri do
    Environment.app_url(path: ~p"/integrations/slack/callback")
  end

  defp render_popup_close(conn, channel_token) do
    conn
    |> put_view(TuistWeb.SlackOAuthHTML)
    |> put_layout(false)
    |> render("popup_close.html", channel_token: channel_token)
  end
end
