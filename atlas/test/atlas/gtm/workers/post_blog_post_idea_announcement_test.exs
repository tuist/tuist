defmodule Atlas.GTM.Workers.PostBlogPostIdeaAnnouncementTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.GTM
  alias Atlas.GTM.BlogPostIdeaNotifier
  alias Atlas.GTM.Workers.PostBlogPostIdeaAnnouncement

  setup :verify_on_exit!

  defp perform(idea_id) do
    PostBlogPostIdeaAnnouncement.perform(%Oban.Job{args: %{"blog_post_idea_id" => idea_id}})
  end

  test "stores the announced thread on the idea" do
    {:ok, idea} = GTM.create_blog_post_idea(%{"title" => "Announce me"})

    expect(BlogPostIdeaNotifier, :announce, fn announced ->
      assert announced.id == idea.id
      {:ok, "1717400000.000100"}
    end)

    assert :ok = perform(idea.id)

    assert GTM.get_blog_post_idea(idea.id).slack_thread_ts == "1717400000.000100"
  end

  test "returns Slack errors so Oban can retry" do
    {:ok, idea} = GTM.create_blog_post_idea(%{"title" => "Flaky Slack"})

    expect(BlogPostIdeaNotifier, :announce, fn _idea -> {:error, :slack_down} end)

    assert {:error, :slack_down} = perform(idea.id)
  end

  test "cancels when the idea no longer exists" do
    assert {:cancel, :idea_not_found} = perform(Ecto.UUID.generate())
  end
end
