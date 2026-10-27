defmodule SlackWeb.InvitationRequestLiveTest do
  use SlackWeb.ConnCase, async: true
  use Mimic

  import Swoosh.TestAssertions

  alias Slack.Captcha
  alias Slack.Invitations

  @valid_reason "We use Tuist to speed up our CI builds and want to chat with other users."

  describe "GET /" do
    test "renders the invitation form with the Code of Conduct", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Join the Tuist Slack"
      assert html =~ "What brought you to Tuist?"
      assert html =~ "Code of conduct"
      assert html =~ "I agree to follow the Code of Conduct"
      assert html =~ "Request invitation"
    end
  end

  describe "submit" do
    test "creates an unconfirmed invitation and emails a confirmation link", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html =
        view
        |> form("#invitation-form",
          invitation: %{
            email: "friend@tuist.dev",
            reason: @valid_reason,
            code_of_conduct_accepted: "true"
          }
        )
        |> render_submit()

      assert html =~ "Check your inbox to confirm your email address."

      assert [invitation] = Invitations.list_invitations(statuses: [:unconfirmed])
      assert invitation.email == "friend@tuist.dev"
      assert invitation.reason == @valid_reason
      assert invitation.code_of_conduct_accepted == true
      assert invitation.status == :unconfirmed

      assert_email_sent(fn email ->
        assert email.to == [{"", "friend@tuist.dev"}]

        assert email.text_body =~
                 "/invitations/confirm/#{invitation.confirmation_token}"
      end)
    end

    test "shows a validation error for an invalid email", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html =
        view
        |> form("#invitation-form",
          invitation: %{
            email: "nope",
            reason: @valid_reason,
            code_of_conduct_accepted: "true"
          }
        )
        |> render_submit()

      assert html =~ "must be a valid email address"
      assert Invitations.list_invitations(statuses: [:unconfirmed]) == []
      assert_no_email_sent()
    end

    test "shows a validation error when the reason is missing", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html =
        view
        |> form("#invitation-form",
          invitation: %{
            email: "friend@tuist.dev",
            reason: "",
            code_of_conduct_accepted: "true"
          }
        )
        |> render_submit()

      assert html =~ "can&#39;t be blank"
      assert Invitations.list_invitations(statuses: [:unconfirmed]) == []
      assert_no_email_sent()
    end

    test "requires the code of conduct checkbox", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html =
        view
        |> form("#invitation-form",
          invitation: %{
            email: "friend@tuist.dev",
            reason: @valid_reason
          }
        )
        |> render_submit()

      assert html =~ "must be accepted to continue"
      assert Invitations.list_invitations(statuses: [:unconfirmed]) == []
      assert_no_email_sent()
    end
  end

  describe "captcha" do
    test "blocks submissions when Cloudflare rejects the token", %{conn: conn} do
      stub(Captcha, :enabled?, fn -> true end)
      stub(Captcha, :site_key, fn -> "test-site-key" end)
      stub(Captcha, :verify, fn _token, _ip -> {:error, {:captcha_failed, ["invalid-input"]}} end)

      {:ok, view, html} = live(conn, ~p"/")
      assert html =~ "test-site-key"

      html =
        view
        |> form("#invitation-form",
          invitation: %{
            email: "captcha@tuist.dev",
            reason: @valid_reason,
            code_of_conduct_accepted: "true"
          }
        )
        |> render_submit()

      assert html =~ "The challenge did not pass"
      assert Invitations.list_invitations(statuses: [:unconfirmed]) == []
      assert_no_email_sent()
    end

    test "lets submissions through when captcha verification passes", %{conn: conn} do
      stub(Captcha, :enabled?, fn -> true end)
      stub(Captcha, :site_key, fn -> "test-site-key" end)
      stub(Captcha, :verify, fn _token, _ip -> :ok end)

      {:ok, view, _html} = live(conn, ~p"/")

      html =
        view
        |> form("#invitation-form",
          invitation: %{
            email: "captcha-ok@tuist.dev",
            reason: @valid_reason,
            code_of_conduct_accepted: "true"
          }
        )
        |> render_submit()

      assert html =~ "Check your inbox"
      assert [invitation] = Invitations.list_invitations(statuses: [:unconfirmed])
      assert invitation.email == "captcha-ok@tuist.dev"
    end
  end
end
