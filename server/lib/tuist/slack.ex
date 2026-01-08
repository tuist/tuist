defmodule Tuist.Slack do
  @moduledoc ~S"""
  This module provides an API to interact with the Slack API
  """
  alias Tuist.Environment
  alias Tuist.Repo
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

  def generate_state_token(account_id) do
    Phoenix.Token.sign(TuistWeb.Endpoint, "slack_state", %{
      type: :account_installation,
      account_id: account_id
    })
  end

  def generate_channel_selection_token(project_id, account_id) do
    Phoenix.Token.sign(TuistWeb.Endpoint, "slack_state", %{
      type: :channel_selection,
      project_id: project_id,
      account_id: account_id
    })
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
end
