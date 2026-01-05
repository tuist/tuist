defmodule Tuist.Slack do
  @moduledoc ~S"""
  This module provides an API to interact with the Slack API
  """
  import Ecto.Query

  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.Repo
  alias Tuist.Slack.Alert
  alias Tuist.Slack.Client
  alias Tuist.Slack.Installation

  @api_url "https://slack.com/api/chat.postMessage"

  def create_installation(attrs) do
    %Installation{}
    |> Installation.changeset(attrs)
    |> Repo.insert()
  end

  def update_installation(installation, attrs) do
    installation
    |> Installation.changeset(attrs)
    |> Repo.update()
  end

  def delete_installation(installation) do
    Repo.delete(installation)
  end

  @doc """
  Gets all channels available to a Slack installation.
  Results are cached for 15 minutes.
  """
  def get_installation_channels(%Installation{team_id: team_id, access_token: access_token}) do
    KeyValueStore.get_or_update(
      [__MODULE__, "channels", team_id],
      [ttl: to_timeout(minute: 15)],
      fn ->
        Client.list_all_channels(access_token)
      end
    )
  end

  def generate_state_token(account_id) do
    Phoenix.Token.sign(TuistWeb.Endpoint, "slack_state", account_id)
  end

  def verify_state_token(token) do
    token_max_age_seconds = 600
    Phoenix.Token.verify(TuistWeb.Endpoint, "slack_state", token, max_age: token_max_age_seconds)
  end

  def send_message(blocks, opts \\ []) do
    if Environment.tuist_hosted?() and Environment.prod?() do
      token = Environment.slack_tuist_token()

      channel =
        Keyword.get(
          opts,
          :channel,
          if(Environment.prod?(), do: "#notifications", else: "#notifications-non-prod")
        )

      headers = [
        {"Authorization", "Bearer #{token}"},
        {"Content-Type", "application/json"}
      ]

      body = Jason.encode!(%{channel: channel, blocks: blocks})

      response =
        @api_url
        |> Req.post(headers: headers, body: body)
        |> handle_response()

      case response do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end

  defp handle_response({:ok, %Req.Response{status: 200, body: body}}) do
    {:ok, body}
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}) do
    {:error, "Unexpected status code: #{status}. Body: #{Jason.encode!(body)}"}
  end

  defp handle_response({:error, reason}) do
    {:error, "Request failed: #{inspect(reason)}"}
  end

  # Alert CRUD functions

  def list_project_alerts(project_id) do
    Alert
    |> where([a], a.project_id == ^project_id)
    |> order_by([a], asc: a.inserted_at)
    |> Repo.all()
  end

  def get_alert(id) do
    case Repo.get(Alert, id) do
      nil -> {:error, :not_found}
      alert -> {:ok, alert}
    end
  end

  def create_alert(attrs) do
    %Alert{}
    |> Alert.changeset(attrs)
    |> Repo.insert()
  end

  def update_alert(alert, attrs) do
    alert
    |> Alert.changeset(attrs)
    |> Repo.update()
  end

  def delete_alert(alert) do
    Repo.delete(alert)
  end

  def list_enabled_alerts do
    Alert
    |> where([a], a.enabled == true)
    |> Repo.all()
    |> Repo.preload(project: [account: :slack_installation])
  end

  def update_alert_triggered_at(alert) do
    alert
    |> Ecto.Changeset.change(last_triggered_at: DateTime.utc_now())
    |> Repo.update()
  end

  def cooldown_elapsed?(alert) do
    case alert.last_triggered_at do
      nil ->
        true

      last_triggered ->
        hours_since = DateTime.diff(DateTime.utc_now(), last_triggered, :hour)
        hours_since >= 24
    end
  end
end
