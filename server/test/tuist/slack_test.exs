defmodule Tuist.SlackTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.Slack

  setup do
    stub(Environment, :prod?, fn -> true end)
    stub(Environment, :tuist_hosted?, fn -> true end)
    :ok
  end

  describe "send_message" do
    test "when the response is successful" do
      # Given
      token = "token"
      stub(Environment, :slack_tuist_token, fn -> token end)

      stub(Req, :post, fn _, [headers: _, body: _] ->
        {:ok, %Req.Response{status: 200, body: %{}}}
      end)

      # When
      response = Slack.send_message(%{})

      # Then
      assert response == :ok
    end

    test "when the response is not successful" do
      # Given
      token = "token"
      stub(Environment, :slack_tuist_token, fn -> token end)

      stub(Req, :post, fn _, [headers: _, body: _] ->
        {:ok, %Req.Response{status: 400, body: %{}}}
      end)

      # When
      response = Slack.send_message(%{})

      # Then
      assert response == {:error, "Unexpected status code: 400. Body: {}"}
    end

    test "when the request fails" do
      # Given
      token = "token"
      stub(Environment, :slack_tuist_token, fn -> token end)
      stub(Req, :post, fn _, [headers: _, body: _] -> {:error, "error"} end)

      # When
      response = Slack.send_message(%{})

      # Then
      assert response == {:error, "Request failed: \"error\""}
    end
  end
end
