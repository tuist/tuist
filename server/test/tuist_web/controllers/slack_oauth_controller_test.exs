defmodule TuistWeb.SlackOAuthControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.Slack
  alias Tuist.Slack.Client, as: SlackClient
  alias TuistWeb.Errors.BadRequestError

  describe "GET /integrations/slack/callback" do
    test "raises BadRequestError when state token is invalid", %{conn: conn} do
      # Given
      invalid_state_token = "invalid_token"

      # When/Then
      assert_raise BadRequestError, ~r/Invalid authorization request/, fn ->
        get(conn, "/integrations/slack/callback", %{"code" => "valid_code", "state" => invalid_state_token})
      end
    end

    test "raises BadRequestError with expiration message when state token is expired", %{conn: conn} do
      # Given
      stub(Slack, :verify_state_token, fn _token -> {:error, :expired} end)

      # When/Then
      assert_raise BadRequestError, ~r/Authorization request expired/, fn ->
        get(conn, "/integrations/slack/callback", %{"code" => "valid_code", "state" => "expired_token"})
      end
    end

    test "raises BadRequestError when code parameter is missing", %{conn: conn} do
      # When/Then
      assert_raise BadRequestError, ~r/Invalid Slack authorization/, fn ->
        get(conn, "/integrations/slack/callback", %{"state" => "some_state"})
      end
    end

    test "raises BadRequestError when state parameter is missing", %{conn: conn} do
      # When/Then
      assert_raise BadRequestError, ~r/Invalid Slack authorization/, fn ->
        get(conn, "/integrations/slack/callback", %{"code" => "valid_code"})
      end
    end

    test "raises BadRequestError when code is empty string", %{conn: conn} do
      # When/Then
      assert_raise BadRequestError, ~r/Invalid Slack authorization/, fn ->
        get(conn, "/integrations/slack/callback", %{"code" => "", "state" => "some_state"})
      end
    end

    test "renders popup_close template with a signed channel token", %{conn: conn} do
      # Given
      project_id = "00000000-0000-0000-0000-000000000001"
      account_id = 1
      state_token = Slack.generate_channel_selection_token(project_id, account_id)

      token_data = %{
        access_token: "xoxb-test-token",
        team_id: "T12345",
        team_name: "Test Workspace",
        bot_user_id: "U12345",
        incoming_webhook: %{
          channel: "#general",
          channel_id: "C12345",
          url: "https://hooks.slack.com/services/T12345/B12345/abcdef"
        }
      }

      stub(SlackClient, :exchange_code_for_token, fn _code, _redirect_uri ->
        {:ok, token_data}
      end)

      # When
      conn = get(conn, "/integrations/slack/callback", %{"code" => "valid_code", "state" => state_token})

      # Then
      html = html_response(conn, 200)
      assert html =~ "Channel connected successfully"
      # Raw webhook URL must NOT appear in the popup HTML — only the signed token does
      refute html =~ "hooks.slack.com"

      [_, channel_token] = Regex.run(~r/data-channel-token="([^"]+)"/, html)

      assert {:ok, %{channel_id: "C12345", channel_name: "general", webhook_url: webhook_url}} =
               Slack.verify_channel_result(channel_token)

      assert webhook_url == "https://hooks.slack.com/services/T12345/B12345/abcdef"
    end

    test "rejects an exchange that returns a non-Slack webhook URL", %{conn: conn} do
      # Given
      project_id = "00000000-0000-0000-0000-000000000001"
      account_id = 1
      state_token = Slack.generate_channel_selection_token(project_id, account_id)

      token_data = %{
        access_token: "xoxb-test-token",
        team_id: "T12345",
        team_name: "Test Workspace",
        bot_user_id: "U12345",
        incoming_webhook: %{
          channel: "#general",
          channel_id: "C12345",
          url: "https://attacker.example.com/hook"
        }
      }

      stub(SlackClient, :exchange_code_for_token, fn _code, _redirect_uri ->
        {:ok, token_data}
      end)

      # When/Then
      assert_raise BadRequestError, ~r/unexpected webhook URL/i, fn ->
        get(conn, "/integrations/slack/callback", %{"code" => "valid_code", "state" => state_token})
      end
    end
  end

  describe "channel_selection_url/2" do
    test "generates correct Slack OAuth URL with incoming-webhook scope" do
      # Given
      project_id = 123
      account_id = 456

      stub(Environment, :slack_client_id, fn -> "test_client_id" end)
      stub(Environment, :app_url, fn opts -> "https://app.tuist.dev" <> Keyword.get(opts, :path, "") end)

      # When
      url = TuistWeb.SlackOAuthController.channel_selection_url(project_id, account_id)

      # Then
      assert url =~ "https://slack.com/oauth/v2/authorize?"
      assert url =~ "client_id=test_client_id"
      assert url =~ "scope=incoming-webhook"
      assert url =~ "redirect_uri=https%3A%2F%2Fapp.tuist.dev%2Fintegrations%2Fslack%2Fcallback"
      assert url =~ "state="
    end
  end
end
