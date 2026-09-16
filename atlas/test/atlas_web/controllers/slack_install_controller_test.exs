defmodule AtlasWeb.SlackInstallControllerTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  alias Atlas.Slack.Installation
  alias Atlas.Slack.Installations

  setup :verify_on_exit!

  test "redirects executives to Slack authorization", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "slack-install-executive@example.com", role: :executive})

    expect(Installations, :authorize_url, fn redirect_uri, state, _config ->
      assert redirect_uri == "http://localhost/slack/install/callback"
      assert is_binary(state)

      {:ok, "https://slack.com/oauth/v2/authorize?state=#{state}"}
    end)

    conn = get(conn, ~p"/slack/install")

    assert redirected_to(conn) =~ "https://slack.com/oauth/v2/authorize?"
  end

  test "redirects employees away from Slack authorization", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "slack-install-employee@example.com", role: :employee})

    conn = get(conn, ~p"/slack/install")

    assert redirected_to(conn) == ~p"/sales"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "You do not have access to manage Slack installs."
  end

  test "completes a valid Slack callback", %{conn: conn} do
    {conn, user} = log_in_user(conn, %{email: "slack-install-callback@example.com", role: :executive})
    state = Phoenix.Token.sign(AtlasWeb.Endpoint, "slack_install", %{nonce: "nonce", user_id: user.id})

    expect(Installations, :complete_install, fn "oauth-code", redirect_uri, opts ->
      assert redirect_uri == "http://localhost/slack/install/callback"
      assert opts[:installed_by_user_id] == user.id
      assert opts[:actor] == user

      {:ok, %Installation{team_id: "T_COMPANY", team_name: "Company"}}
    end)

    conn = get(conn, ~p"/slack/install/callback?code=oauth-code&state=#{state}")

    assert redirected_to(conn) == ~p"/admin/identities"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Connected Company to Atlas."
  end

  test "rejects callbacks created for another user", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "slack-install-mismatch@example.com", role: :executive})
    state = Phoenix.Token.sign(AtlasWeb.Endpoint, "slack_install", %{nonce: "nonce", user_id: "other-user"})

    conn = get(conn, ~p"/slack/install/callback?code=oauth-code&state=#{state}")

    assert redirected_to(conn) == ~p"/admin/identities"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "The Slack install link was created for a different Atlas session. Try again."
  end
end
