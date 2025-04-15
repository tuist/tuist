defmodule Tuist.Slack do
  @moduledoc ~S"""
  This module provides an API to interact with the Slack API
  """
  alias Tuist.Environment

  @api_url "https://slack.com/api/chat.postMessage"

  def send_message(blocks, opts \\ []) do
    if not Environment.on_premise?() and Environment.prod?() do
      token = Environment.slack_tuist_token()
      channel = Keyword.get(opts, :channel, "#notifications")

      headers = [
        {"Authorization", "Bearer #{token}"},
        {"Content-Type", "application/json"}
      ]

      body =
        %{
          channel: channel,
          blocks: blocks
        }
        |> Jason.encode!()

      response =
        Req.post(@api_url, headers: headers, body: body)
        |> handle_response()

      case response do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
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
