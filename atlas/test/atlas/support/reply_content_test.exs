defmodule Atlas.Support.ReplyContentTest do
  use ExUnit.Case, async: true

  alias Atlas.Support.ReplyContent

  test "removes Gmail reply history and signatures from the visible body" do
    body = """
    I am following up on this request.

    On Tue, Aug 25, 2026 at 4:20 PM Tuist Support <contact@tuist.dev> wrote:

    > How are you?
    >
    > --
    > Pedro Piñera

    --
    Pedro Piñera
    """

    assert ReplyContent.visible(body) == "I am following up on this request."
  end

  test "preserves content when it contains no reply history" do
    assert ReplyContent.visible("Thanks for the quick reply.") == "Thanks for the quick reply."
  end

  test "preserves a sentence that resembles a Gmail reply delimiter" do
    body = """
    On Tuesday, we wrote:
    Please add this clarification to the customer-facing documentation.
    """

    assert ReplyContent.visible(body) ==
             "On Tuesday, we wrote:\nPlease add this clarification to the customer-facing documentation."
  end

  test "removes Outlook reply history" do
    body = """
    Please use the updated bank details.

    From: Tuist Support <contact@tuist.dev>
    Sent: Monday, August 17, 2026 9:16 AM
    To: Diana J Winterroth <diana@example.com>
    Cc: Pedro <pedro@tuist.dev>
    Subject: Re: Wire transfer

    Hi Diana,
    """

    assert ReplyContent.visible(body) == "Please use the updated bank details."
  end

  test "extracts inline attachment identifiers while hiding their text markers" do
    body = """
    Please see the screenshots below.
    [cid:image003.png@example.com]
    [cid:image005.png@example.com]
    """

    assert ReplyContent.visible(body) == "Please see the screenshots below."

    assert ReplyContent.inline_attachment_ids(body) == [
             "image003.png@example.com",
             "image005.png@example.com"
           ]
  end
end
