defmodule Tuist.Slack.ClientTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.Slack.Client

  describe "exchange_code_for_token/2" do
    test "returns token data on successful response" do
      stub(Environment, :slack_client_id, fn -> "client-id" end)
      stub(Environment, :slack_client_secret, fn -> "client-secret" end)

      stub(Req, :post, fn _url, _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "ok" => true,
             "access_token" => "xoxb-test-token",
             "team" => %{"id" => "T12345", "name" => "Test Workspace"},
             "bot_user_id" => "U12345"
           }
         }}
      end)

      result = Client.exchange_code_for_token("auth-code", "https://example.com/callback")

      assert {:ok, token_data} = result
      assert token_data.access_token == "xoxb-test-token"
      assert token_data.team_id == "T12345"
      assert token_data.team_name == "Test Workspace"
      assert token_data.bot_user_id == "U12345"
    end

    test "returns error when Slack API returns error" do
      stub(Environment, :slack_client_id, fn -> "client-id" end)
      stub(Environment, :slack_client_secret, fn -> "client-secret" end)

      stub(Req, :post, fn _url, _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body: %{"ok" => false, "error" => "invalid_code"}
         }}
      end)

      result = Client.exchange_code_for_token("invalid-code", "https://example.com/callback")

      assert {:error, "invalid_code"} = result
    end

    test "returns error on unexpected status code" do
      stub(Environment, :slack_client_id, fn -> "client-id" end)
      stub(Environment, :slack_client_secret, fn -> "client-secret" end)

      stub(Req, :post, fn _url, _opts ->
        {:ok, %Req.Response{status: 500, body: %{"error" => "server_error"}}}
      end)

      result = Client.exchange_code_for_token("auth-code", "https://example.com/callback")

      assert {:error, message} = result
      assert message =~ "Unexpected status code: 500"
    end

    test "returns error when request fails" do
      stub(Environment, :slack_client_id, fn -> "client-id" end)
      stub(Environment, :slack_client_secret, fn -> "client-secret" end)

      stub(Req, :post, fn _url, _opts ->
        {:error, %Req.TransportError{reason: :timeout}}
      end)

      result = Client.exchange_code_for_token("auth-code", "https://example.com/callback")

      assert {:error, message} = result
      assert message =~ "Request failed"
    end

    test "includes incoming_webhook data when present in response" do
      stub(Environment, :slack_client_id, fn -> "client-id" end)
      stub(Environment, :slack_client_secret, fn -> "client-secret" end)

      stub(Req, :post, fn _url, _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "ok" => true,
             "access_token" => "xoxb-test-token",
             "team" => %{"id" => "T12345", "name" => "Test Workspace"},
             "bot_user_id" => "U12345",
             "incoming_webhook" => %{
               "channel" => "#general",
               "channel_id" => "C123456",
               "url" => "https://hooks.slack.com/services/xxx"
             }
           }
         }}
      end)

      result = Client.exchange_code_for_token("auth-code", "https://example.com/callback")

      assert {:ok, token_data} = result
      assert token_data.access_token == "xoxb-test-token"
      assert token_data.incoming_webhook.channel == "#general"
      assert token_data.incoming_webhook.channel_id == "C123456"
    end
  end

  describe "post_message/3" do
    test "returns :ok on successful post" do
      stub(Req, :post, fn _url, _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body: %{"ok" => true}
         }}
      end)

      result = Client.post_message("xoxb-token", "C123", [%{type: "section", text: "Hello"}])

      assert :ok = result
    end

    test "returns error when Slack API returns error" do
      stub(Req, :post, fn _url, _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body: %{"ok" => false, "error" => "channel_not_found"}
         }}
      end)

      result = Client.post_message("xoxb-token", "invalid-channel", [])

      assert {:error, "channel_not_found"} = result
    end

    test "returns error on unexpected status code" do
      stub(Req, :post, fn _url, _opts ->
        {:ok, %Req.Response{status: 500, body: %{}}}
      end)

      result = Client.post_message("xoxb-token", "C123", [])

      assert {:error, message} = result
      assert message =~ "Unexpected status code: 500"
    end

    test "returns error when request fails" do
      stub(Req, :post, fn _url, _opts ->
        {:error, %Req.TransportError{reason: :timeout}}
      end)

      result = Client.post_message("xoxb-token", "C123", [])

      assert {:error, message} = result
      assert message =~ "Request failed"
    end
  end
end
