defmodule TuistWeb.SlackOAuthControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.Slack
  alias Tuist.Slack.Client, as: SlackClient
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.Errors.BadRequestError

  describe "GET /integrations/slack/callback" do
    test "redirects to integrations page on successful OAuth flow", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      account = user.account
      state_token = Slack.generate_state_token(account.id)

      token_data = %{
        access_token: "xoxb-test-token",
        team_id: "T12345",
        team_name: "Test Workspace",
        bot_user_id: "U12345"
      }

      stub(SlackClient, :exchange_code_for_token, fn _code, _redirect_uri ->
        {:ok, token_data}
      end)

      # When
      conn = get(conn, "/integrations/slack/callback", %{"code" => "valid_code", "state" => state_token})

      # Then
      assert redirected_to(conn) == "/#{account.name}/integrations"

      {:ok, updated_account} = Accounts.get_account_by_id(account.id, preload: [:slack_installation])
      assert updated_account.slack_installation.team_id == "T12345"
      assert updated_account.slack_installation.team_name == "Test Workspace"
      assert updated_account.slack_installation.bot_user_id == "U12345"
    end

    test "raises BadRequestError when state token is invalid", %{conn: conn} do
      # Given
      invalid_state_token = "invalid_token"

      # When/Then
      assert_raise BadRequestError, ~r/Invalid authorization request/, fn ->
        get(conn, "/integrations/slack/callback", %{"code" => "valid_code", "state" => invalid_state_token})
      end
    end

    test "raises BadRequestError when account is not found", %{conn: conn} do
      # Given
      non_existent_account_id = 999_999_999
      state_token = Slack.generate_state_token(non_existent_account_id)

      # When/Then
      assert_raise BadRequestError, ~r/Account not found/, fn ->
        get(conn, "/integrations/slack/callback", %{"code" => "valid_code", "state" => state_token})
      end
    end

    test "raises BadRequestError when Slack returns an error", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      account = user.account
      state_token = Slack.generate_state_token(account.id)

      stub(SlackClient, :exchange_code_for_token, fn _code, _redirect_uri ->
        {:error, "invalid_code"}
      end)

      # When/Then
      assert_raise BadRequestError, ~r/Slack authorization failed: invalid_code/, fn ->
        get(conn, "/integrations/slack/callback", %{"code" => "invalid_code", "state" => state_token})
      end
    end

    test "raises BadRequestError when installation fails to save", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      account = user.account
      state_token = Slack.generate_state_token(account.id)

      token_data = %{
        access_token: "xoxb-test-token",
        team_id: "T12345",
        team_name: "Test Workspace",
        bot_user_id: "U12345"
      }

      stub(SlackClient, :exchange_code_for_token, fn _code, _redirect_uri ->
        {:ok, token_data}
      end)

      stub(Slack, :create_installation, fn _attrs ->
        {:error, %Ecto.Changeset{}}
      end)

      # When/Then
      assert_raise BadRequestError, ~r/Failed to save Slack installation/, fn ->
        get(conn, "/integrations/slack/callback", %{"code" => "valid_code", "state" => state_token})
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
  end

  describe "install_url/1" do
    test "generates correct Slack OAuth URL" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = user.account

      stub(Environment, :slack_client_id, fn -> "test_client_id" end)
      stub(Environment, :app_url, fn opts -> "https://app.tuist.dev" <> Keyword.get(opts, :path, "") end)

      # When
      url = TuistWeb.SlackOAuthController.install_url(account.id)

      # Then
      assert url =~ "https://slack.com/oauth/v2/authorize?"
      assert url =~ "client_id=test_client_id"
      assert url =~ "scope=chat%3Awrite%2Cchat%3Awrite.public"
      refute url =~ "channels%3Aread"
      refute url =~ "groups%3Aread"
      assert url =~ "redirect_uri=https%3A%2F%2Fapp.tuist.dev%2Fintegrations%2Fslack%2Fcallback"
      assert url =~ "state="
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
