defmodule Atlas.Accounts.POCs.VerificationEmailTest do
  use ExUnit.Case, async: true

  import Swoosh.TestAssertions

  alias Atlas.Accounts.POCs.AccessRequest
  alias Atlas.Accounts.POCs.Notifier
  alias Atlas.Accounts.POCs.POC
  alias Atlas.Accounts.POCs.VerificationEmail

  test "renders the Tuist transactional email design and escapes dynamic content" do
    html = VerificationEmail.render("Acme & Sons", "https://atlas.tuist.dev/verify?token=a&request_id=b")

    assert html =~ ~s(<html lang="en">)
    assert html =~ ~s(<img src="#{AtlasWeb.Endpoint.url()}/images/tuist_email.png")
    assert html =~ "Verify your email to open the Acme &amp; Sons brief"
    assert html =~ ~s(class="button-primary" href="https://atlas.tuist.dev/verify?token=a&amp;request_id=b")
    assert html =~ "Confirm my email"
    assert html =~ "within 15 minutes"
    assert html =~ "terms of service"
    refute html =~ "Acme & Sons"
  end

  test "delivers the designed email with its plain text alternative" do
    poc = %POC{title: "Discovery", account: %{name: "Tuist"}, public_token: "brief-token"}
    request = %AccessRequest{id: "request-id", email: "reader@example.com"}

    assert {:ok, _email} = Notifier.send_verification_email(poc, request, "secret-token")

    assert_email_sent(fn email ->
      assert email.to == [{"", "reader@example.com"}]
      assert email.html_body =~ "Verify your email to open the Tuist brief"
      assert email.html_body =~ "class=\"button-primary\""
      assert email.text_body =~ "Once you confirm, the Tuist team will grant access."
    end)
  end
end
