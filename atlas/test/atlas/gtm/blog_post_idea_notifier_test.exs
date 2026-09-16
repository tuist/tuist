defmodule Atlas.GTM.BlogPostIdeaNotifierTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.GTM
  alias Atlas.GTM.BlogPostIdeaNotifier
  alias Atlas.Slack.API

  setup :verify_on_exit!

  defp build_idea(attrs \\ %{}) do
    {:ok, idea} =
      GTM.create_blog_post_idea(Map.merge(%{"title" => "Caching deep dive", "created_by_agent" => "slack"}, attrs))

    idea
  end

  describe "build_blocks/1" do
    test "renders a rich announcement with title, status, description, and an Atlas link" do
      idea = build_idea(%{"description" => "Benchmarks and tips.", "status" => "in_progress"})

      blocks = BlogPostIdeaNotifier.build_blocks(idea)

      assert %{"type" => "header", "text" => %{"text" => "Caching deep dive"}} = Enum.at(blocks, 0)

      assert Enum.any?(blocks, fn block ->
               block["type"] == "context" and
                 Enum.any?(block["elements"], &(is_binary(&1["text"]) and &1["text"] =~ "In progress"))
             end)

      assert Enum.any?(blocks, fn block ->
               block["type"] == "section" and block["text"]["text"] == "Benchmarks and tips."
             end)

      action = Enum.find(blocks, &(&1["type"] == "actions"))
      [button] = action["elements"]
      assert button["text"]["text"] == "Open in Atlas"
      assert button["url"] =~ "/gtm/content/#{idea.id}"
    end

    test "omits the description block when there is no description" do
      idea = build_idea(%{"description" => nil})
      blocks = BlogPostIdeaNotifier.build_blocks(idea)

      refute Enum.any?(blocks, fn block ->
               block["type"] == "section"
             end)
    end
  end

  describe "announce/1" do
    test "posts to the company #marketing channel and returns the thread ts" do
      idea = build_idea()

      expect(API, :post_message, fn :company, "C0AGV3YU8ET", text, blocks ->
        assert text =~ "Caching deep dive"
        assert is_list(blocks)
        {:ok, %{"ok" => true, "channel" => "C0AGV3YU8ET", "ts" => "1717400000.000100"}}
      end)

      assert {:ok, "1717400000.000100"} = BlogPostIdeaNotifier.announce(idea)
    end

    test "returns the error when Slack rejects the post" do
      idea = build_idea()
      expect(API, :post_message, fn :company, "C0AGV3YU8ET", _text, _blocks -> {:error, :channel_not_found} end)

      assert {:error, :channel_not_found} = BlogPostIdeaNotifier.announce(idea)
    end
  end
end
