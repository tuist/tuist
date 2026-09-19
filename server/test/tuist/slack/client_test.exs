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
      assert message =~ "Slack OAuth responded 500"
    end

    test "returns error when request fails" do
      stub(Environment, :slack_client_id, fn -> "client-id" end)
      stub(Environment, :slack_client_secret, fn -> "client-secret" end)

      stub(Req, :post, fn _url, _opts ->
        {:error, %Req.TransportError{reason: :timeout}}
      end)

      result = Client.exchange_code_for_token("auth-code", "https://example.com/callback")

      assert {:error, message} = result
      assert message =~ "Slack OAuth request failed"
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
      assert token_data.incoming_webhook.url == "https://hooks.slack.com/services/xxx"
    end
  end

  describe "post_to_webhook/2" do
    test "returns :ok on successful post" do
      stub(Req, :post, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: "ok"}}
      end)

      result =
        Client.post_to_webhook(
          "https://hooks.slack.com/services/T0/B0/abcd",
          [%{type: "section", text: "Hello"}]
        )

      assert :ok = result
    end

    test "returns :webhook_revoked on 404 (permanent failure)" do
      stub(Req, :post, fn _url, _opts ->
        {:ok, %Req.Response{status: 404, body: "no_service"}}
      end)

      assert {:error, :webhook_revoked} =
               Client.post_to_webhook("https://hooks.slack.com/services/T0/B0/abcd", [])
    end

    test "returns :webhook_revoked on Slack's permanent auth/team errors" do
      cases = [
        {400, "invalid_token"},
        {401, "invalid_token"},
        {403, "action_prohibited"},
        {400, "team_disabled"},
        {400, "no_team"},
        {400, "no_service_id"}
      ]

      for {status, reason} <- cases do
        stub(Req, :post, fn _url, _opts ->
          {:ok, %Req.Response{status: status, body: reason}}
        end)

        assert {:error, :webhook_revoked} =
                 Client.post_to_webhook("https://hooks.slack.com/services/T0/B0/abcd", []),
               "expected :webhook_revoked for #{status} #{reason}"
      end
    end

    test "returns {:bad_request, status, response_body, request_body} on an unrecognized 4xx" do
      stub(Req, :post, fn _url, opts ->
        # The client passes its serialized request body through so the
        # caller can attach it to the alert. Echo it into the error tuple
        # via the stub so we can assert the same bytes come back.
        send(self(), {:request_body, opts[:body]})
        {:ok, %Req.Response{status: 400, body: "invalid_payload"}}
      end)

      assert {:error, {:bad_request, 400, "invalid_payload", request_body}} =
               Client.post_to_webhook(
                 "https://hooks.slack.com/services/T0/B0/abcd",
                 [%{type: "section", text: "Hi"}]
               )

      assert_received {:request_body, sent}
      assert request_body == sent
      assert request_body =~ ~s("blocks")
      assert request_body =~ ~s("Hi")
    end

    test "returns a transient error on a 5xx" do
      stub(Req, :post, fn _url, _opts ->
        {:ok, %Req.Response{status: 500, body: "boom"}}
      end)

      result = Client.post_to_webhook("https://hooks.slack.com/services/T0/B0/abcd", [])

      assert {:error, message} = result
      assert message =~ "Slack incoming-webhook responded 500 with response body"
    end

    test "returns error when request fails" do
      stub(Req, :post, fn _url, _opts ->
        {:error, %Req.TransportError{reason: :timeout}}
      end)

      result = Client.post_to_webhook("https://hooks.slack.com/services/T0/B0/abcd", [])

      assert {:error, message} = result
      assert message =~ "Slack incoming-webhook request failed"
    end
  end
end
