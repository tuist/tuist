defmodule Atlas.Support.EmailTest do
  use ExUnit.Case, async: true

  alias Atlas.Support.Email
  alias Atlas.Support.Message
  alias Atlas.Support.Thread

  test "renders replies as semantic HTML without branded presentation styles" do
    assert {:ok, email} =
             Email.reply(
               %Thread{subject: "A question"},
               %Message{
                 message_id: "reply@example.com",
                 sender_email: "contact@tuist.dev",
                 to_emails: ["customer@example.com"],
                 body: "# Hello\n\n**Thanks** for [writing](https://tuist.dev).\n\n- First\n- Second"
               }
             )

    assert email.html_body =~ "<h1>Hello</h1>"
    assert email.html_body =~ "<strong>Thanks</strong>"
    assert email.html_body =~ ~s(href="https://tuist.dev")
    assert email.html_body =~ "<li>First</li>"
    refute email.html_body =~ "style="
    refute email.html_body =~ "max-width"

    assert email.text_body =~ "Thanks for writing: https://tuist.dev"
    refute email.text_body =~ "**"
  end

  test "preserves single line breaks in the HTML and text email bodies" do
    assert {:ok, email} =
             Email.reply(
               %Thread{subject: "A question"},
               %Message{
                 message_id: "reply@example.com",
                 sender_email: "contact@tuist.dev",
                 to_emails: ["customer@example.com"],
                 body: "Hello,\nThanks for writing."
               }
             )

    assert email.html_body =~ "Hello,<br"
    assert email.text_body =~ "Hello,\nThanks for writing."
  end
end
