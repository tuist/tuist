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
  end

  describe "list_channels/2" do
    test "returns channels on successful response" do
      stub(Req, :get, fn _url, _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "ok" => true,
             "channels" => [
               %{"id" => "C123", "name" => "general", "is_private" => false},
               %{"id" => "C456", "name" => "random", "is_private" => false}
             ],
             "response_metadata" => %{"next_cursor" => ""}
           }
         }}
      end)

      result = Client.list_channels("xoxb-token")

      assert {:ok, channels, cursor} = result
      assert length(channels) == 2
      assert Enum.at(channels, 0).id == "C123"
      assert Enum.at(channels, 0).name == "general"
      assert Enum.at(channels, 1).id == "C456"
      assert cursor == ""
    end

    test "returns next cursor for pagination" do
      stub(Req, :get, fn _url, _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "ok" => true,
             "channels" => [%{"id" => "C123", "name" => "general", "is_private" => false}],
             "response_metadata" => %{"next_cursor" => "dXNlcjpVMDYxVEtSUlA="}
           }
         }}
      end)

      result = Client.list_channels("xoxb-token")

      assert {:ok, _channels, cursor} = result
      assert cursor == "dXNlcjpVMDYxVEtSUlA="
    end

    test "returns error when Slack API returns error" do
      stub(Req, :get, fn _url, _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body: %{"ok" => false, "error" => "invalid_auth"}
         }}
      end)

      result = Client.list_channels("invalid-token")

      assert {:error, "invalid_auth"} = result
    end

    test "returns error on unexpected status code" do
      stub(Req, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 500, body: %{}}}
      end)

      result = Client.list_channels("xoxb-token")

      assert {:error, message} = result
      assert message =~ "Unexpected status code: 500"
    end

    test "returns error when request fails" do
      stub(Req, :get, fn _url, _opts ->
        {:error, %Req.TransportError{reason: :timeout}}
      end)

      result = Client.list_channels("xoxb-token")

      assert {:error, message} = result
      assert message =~ "Request failed"
    end
  end

  describe "list_all_channels/1" do
    test "returns all channels when no pagination needed" do
      stub(Req, :get, fn _url, _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "ok" => true,
             "channels" => [
               %{"id" => "C123", "name" => "general", "is_private" => false},
               %{"id" => "C456", "name" => "random", "is_private" => false}
             ],
             "response_metadata" => %{"next_cursor" => ""}
           }
         }}
      end)

      result = Client.list_all_channels("xoxb-token")

      assert {:ok, channels} = result
      assert length(channels) == 2
    end

    test "fetches all pages when pagination is needed" do
      call_count = :counters.new(1, [:atomics])

      stub(Req, :get, fn _url, opts ->
        :counters.add(call_count, 1, 1)
        count = :counters.get(call_count, 1)

        if count == 1 do
          {:ok,
           %Req.Response{
             status: 200,
             body: %{
               "ok" => true,
               "channels" => [%{"id" => "C123", "name" => "general", "is_private" => false}],
               "response_metadata" => %{"next_cursor" => "page2cursor"}
             }
           }}
        else
          assert opts[:params][:cursor] == "page2cursor"

          {:ok,
           %Req.Response{
             status: 200,
             body: %{
               "ok" => true,
               "channels" => [%{"id" => "C456", "name" => "random", "is_private" => false}],
               "response_metadata" => %{"next_cursor" => ""}
             }
           }}
        end
      end)

      result = Client.list_all_channels("xoxb-token")

      assert {:ok, channels} = result
      assert length(channels) == 2
      assert Enum.at(channels, 0).id == "C123"
      assert Enum.at(channels, 1).id == "C456"
    end

    test "returns error if any page fails" do
      stub(Req, :get, fn _url, _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body: %{"ok" => false, "error" => "rate_limited"}
         }}
      end)

      result = Client.list_all_channels("xoxb-token")

      assert {:error, "rate_limited"} = result
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
