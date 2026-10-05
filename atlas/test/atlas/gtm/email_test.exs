defmodule Atlas.GTM.EmailTest do
  use ExUnit.Case, async: true

  alias Atlas.GTM.Delivery
  alias Atlas.GTM.Email

  defp delivery(metadata) do
    %Delivery{
      id: "0199a0d0-0000-7000-8000-000000000001",
      kind: "direct",
      recipient_email: "recipient@example.com",
      recipient_name: "Riley",
      subject: "Your Tuist pricing is changing",
      metadata: metadata
    }
  end

  describe "direct/1" do
    test "renders the body without an unsubscribe affordance" do
      email = Email.direct(delivery(%{"body_markdown" => "Your price changes on 22 October 2026."}))

      assert email.to == [{"Riley", "recipient@example.com"}]
      assert email.subject == "Your Tuist pricing is changing"
      assert email.html_body =~ "Your price changes on 22 October 2026."
      refute email.html_body =~ "Unsubscribe"
      refute email.text_body =~ "Unsubscribe"
      refute Map.has_key?(email.headers, "List-Unsubscribe")
      refute Map.has_key?(email.headers, "List-Unsubscribe-Post")
    end

    test "copies the CC addresses stored on the delivery" do
      email =
        Email.direct(%{
          delivery(%{"body_markdown" => "Hello."})
          | cc_emails: ["cto@acme.example", "ops@acme.example"]
        })

      assert email.to == [{"Riley", "recipient@example.com"}]
      assert email.cc == [{"", "cto@acme.example"}, {"", "ops@acme.example"}]
    end

    test "sends no CC when the delivery has none" do
      email = Email.direct(delivery(%{"body_markdown" => "Hello."}))

      assert email.cc == []
    end

    test "carries a per-delivery provider idempotency key" do
      email = Email.direct(delivery(%{"body_markdown" => "Hello."}))

      assert email.provider_options[:idempotency_key] == "gtm-delivery-0199a0d0-0000-7000-8000-000000000001"
    end

    test "sends from the configured defaults when the caller names no sender" do
      email = Email.direct(delivery(%{"body_markdown" => "Hello."}))
      defaults = Application.get_env(:atlas, :gtm_email, [])

      assert email.from == {defaults[:from_name], defaults[:from_email]}
      assert email.reply_to == {"", defaults[:reply_to_email]}
    end

    test "overrides the sender and reply-to from the delivery" do
      email =
        Email.direct(
          delivery(%{
            "body_markdown" => "Hello.",
            "from_name" => "Tuist Billing",
            "from_email" => "billing@tuist.dev",
            "reply_to_email" => "marek@tuist.dev"
          })
        )

      assert email.from == {"Tuist Billing", "billing@tuist.dev"}
      assert email.reply_to == {"", "marek@tuist.dev"}
    end

    test "renders a GFM table" do
      markdown = """
      | Meter | Included | Rate |
      | --- | --- | --- |
      | Cache egress | 100 GB | $0.35/GB |
      """

      email = Email.direct(delivery(%{"body_markdown" => markdown}))

      assert email.html_body =~ "<table>"
      assert email.html_body =~ "<th>Meter</th>"
      assert email.html_body =~ "<td>Cache egress</td>"
      assert email.html_body =~ ".broadcast-content table"
    end
  end
end
