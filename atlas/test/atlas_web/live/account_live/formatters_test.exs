defmodule AtlasWeb.AccountLive.FormattersTest do
  use ExUnit.Case, async: true

  alias AtlasWeb.AccountLive.Formatters

  test "renders retrieved Slack formatting without leaking control syntax" do
    text =
      "&gt; Are you caching the build directory?\nYes. See <https://sumup.slack.com/archives/C123/p456|the thread> &amp; follow up.\n\n- First step\n- Second step"

    document =
      text
      |> Formatters.slack_message_html()
      |> Phoenix.HTML.safe_to_string()
      |> LazyHTML.from_fragment()

    assert document |> LazyHTML.filter("blockquote") |> LazyHTML.text() |> String.trim() ==
             "Are you caching the build directory?"

    assert document
           |> LazyHTML.query(~s|a[href="https://sumup.slack.com/archives/C123/p456"]|)
           |> LazyHTML.text() ==
             "the thread"

    assert document |> LazyHTML.query("ul li") |> LazyHTML.text() =~ "First step"
    assert LazyHTML.text(document) =~ "Yes. See the thread & follow up."
    refute LazyHTML.text(document) =~ "&gt;"
    refute LazyHTML.text(document) =~ "<https://"
  end

  test "resolves known mentions and keeps unknown mentions readable" do
    document =
      "Hello <@U_PEDRO> and <@U_UNKNOWN>"
      |> Formatters.slack_message_html(%{"U_PEDRO" => "pedro"})
      |> Phoenix.HTML.safe_to_string()
      |> LazyHTML.from_fragment()

    assert LazyHTML.text(document) == "Hello @pedro and @U_UNKNOWN"
  end

  test "keeps encoded markup inert" do
    document =
      "&lt;script&gt;alert('nope')&lt;/script&gt; <javascript:alert(1)|unsafe>"
      |> Formatters.slack_message_html()
      |> Phoenix.HTML.safe_to_string()
      |> LazyHTML.from_fragment()

    refute document |> LazyHTML.query("script") |> Enum.any?()
    refute document |> LazyHTML.query("a") |> Enum.any?()
    assert LazyHTML.text(document) =~ "<script>alert('nope')</script>"
  end
end
