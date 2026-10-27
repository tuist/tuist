defmodule Atlas.Slack.BlogPostIdeaCaptureTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.GTM
  alias Atlas.Slack.API
  alias Atlas.Slack.Events, as: SlackEvents

  setup :verify_on_exit!

  defp announced_idea(thread_ts) do
    {:ok, idea} = GTM.create_blog_post_idea(%{"title" => "Thread idea"})
    {:ok, idea} = GTM.set_blog_post_idea_slack_thread(idea, thread_ts)
    idea
  end

  defp reply_event(attrs) do
    Map.merge(
      %{
        "type" => "message",
        "channel" => "C_MARKETING",
        "thread_ts" => "1717400000.000100",
        "ts" => "1717400500.000200",
        "user" => "U123",
        "text" => "Love this, let's add benchmarks."
      },
      attrs
    )
  end

  test "captures a human reply in an idea thread as a follow-up comment" do
    stub(API, :get_user_info, fn :company, "U123" ->
      {:ok,
       %{
         slack_user_id: "U123",
         name: "alice",
         real_name: "Alice Marketer",
         display_name: "alice",
         avatar_url: nil,
         is_bot: false,
         is_external: false
       }}
    end)

    idea = announced_idea("1717400000.000100")

    SlackEvents.handle_event(reply_event(%{}), :company)

    idea = GTM.get_blog_post_idea(idea.id)
    assert [comment] = idea.comments
    assert comment.body == "Love this, let's add benchmarks."
    assert is_binary(comment.author_name)
  end

  test "ignores replies in threads not tied to an idea" do
    assert :ignored =
             SlackEvents.handle_event(reply_event(%{"thread_ts" => "9999.0000"}), :company)
  end

  test "ignores the bot's own announcement message" do
    idea = announced_idea("1717400000.000100")

    # A top-level (non-thread) bot message echoes the announcement; it must not
    # be captured as a comment on the idea.
    bot_event = %{
      "type" => "message",
      "subtype" => "bot_message",
      "channel" => "C_MARKETING",
      "ts" => "1717400000.000100",
      "bot_id" => "B999",
      "text" => "New blog post idea: Thread idea"
    }

    assert :ignored = SlackEvents.handle_event(bot_event, :company)

    assert GTM.get_blog_post_idea(idea.id).comments == []
  end
end
