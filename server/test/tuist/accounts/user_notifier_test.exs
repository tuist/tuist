defmodule Tuist.Accounts.UserNotifierTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts.User
  alias Tuist.Accounts.UserNotifier
  alias Tuist.Environment

  setup do
    stub(Environment, :mailing_from_address, fn -> "noreply@tuist.dev" end)
    stub(Environment, :mailing_reply_to_address, fn -> nil end)

    %{user: %User{email: "ada@tuist.dev", account: %{name: "ada"}}}
  end

  describe "the shared template" do
    test "renders the masthead, content box, button and footer as email-safe markup", %{user: user} do
      {:ok, email} =
        UserNotifier.deliver_confirmation_instructions(%{
          user: user,
          confirmation_url: "https://tuist.dev/confirm?token=abc"
        })

      assert email.to == [nil: "ada@tuist.dev"]
      assert email.subject == "Confirmation instructions"
      assert email.html_body =~ ~s(<table role="presentation")
      assert email.html_body =~ "/images/tuist_email.png"
      assert email.html_body =~ "You&#39;re Almost Set!"
      assert email.html_body =~ ~s(class="button-primary" href="https://tuist.dev/confirm?token=abc")
      assert email.html_body =~ "rgb(111, 44, 255)"
      assert email.html_body =~ "[data-ogsc] .button-primary"
      assert email.html_body =~ "Tuist GmbH #{Date.utc_today().year}"
      refute email.html_body =~ "#622ED4"
    end

    test "escapes interpolated values" do
      email =
        UserNotifier.deliver_invitation("guest@example.com", %{
          inviter: %User{email: "boss@example.com"},
          to: %{account: %{name: "<script>alert(1)</script>"}},
          url: "https://tuist.dev/invite"
        })

      refute email.html_body =~ "<script>alert(1)</script>"
      assert email.html_body =~ "&lt;script&gt;alert(1)&lt;/script&gt;"
    end
  end

  test "deliver_reset_password_instructions/1", %{user: user} do
    email = UserNotifier.deliver_reset_password_instructions(%{user: user, reset_password_url: "https://tuist.dev/reset"})

    assert email.subject == "Reset password instructions"
    assert email.html_body =~ "Hola ada, you can reset your password"
    assert email.html_body =~ ~s(href="https://tuist.dev/reset")
  end

  test "deliver_agent_registration_claim_instructions/1" do
    email =
      UserNotifier.deliver_agent_registration_claim_instructions(%{
        email: "ada@tuist.dev",
        claim_view_url: "https://tuist.dev/agents/claim"
      })

    assert email.subject == "Your Tuist agent sign-in code"
    assert email.html_body =~ "View sign-in code"
    assert email.html_body =~ ~s(href="https://tuist.dev/agents/claim")
  end

  test "deliver_scim_organization_attachment/2", %{user: user} do
    {:ok, email} = UserNotifier.deliver_scim_organization_attachment(user, %{account: %{name: "acme"}})

    assert email.subject == "You were added to the acme Tuist organization"
    assert email.html_body =~ "automated user provisioning (SCIM)"
    assert email.html_body =~ "Open acme"
  end

  test "deliver_update_email_instructions/2 renders the shared template", %{user: user} do
    email = UserNotifier.deliver_update_email_instructions(user, "https://tuist.dev/users/settings/confirm_email/abc")

    assert email.subject == "Update email instructions"
    assert email.html_body =~ ~s(<table role="presentation")
    assert email.html_body =~ ~s(href="https://tuist.dev/users/settings/confirm_email/abc")
    refute email.html_body =~ "=============================="
  end
end
