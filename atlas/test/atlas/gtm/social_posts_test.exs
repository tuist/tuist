defmodule Atlas.GTM.SocialPostsTest do
  use Atlas.DataCase, async: true
  use Mimic

  import Atlas.MCP.ToolCase, only: [insert_user!: 0, mcp_conn: 1]

  alias Atlas.Connections.Connection
  alias Atlas.GTM.SocialPost
  alias Atlas.GTM.SocialPosts
  alias Atlas.GTM.SocialPostSnapshot
  alias Atlas.MCP.Tools.SyncMySocialPosts

  setup do
    user = insert_user!()
    n = System.unique_integer([:positive])
    account_id = "acct#{n}"

    %Connection{user_id: user.id, provider: "x"}
    |> Connection.changeset(%{
      provider_user_id: account_id,
      account_name: "@brand#{n}",
      access_token: "x-access",
      refresh_token: "x-refresh",
      scopes: ["tweet.read", "users.read", "offline.access"],
      expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
    })
    |> Repo.insert!()

    ids =
      for suffix <- ~w(video thread child reply mention link),
          into: %{},
          do: {suffix, "#{n}#{byte_size(suffix)}#{suffix}"}

    %{user: user, account_id: account_id, username: "brand#{n}", ids: ids}
  end

  defp posts(ctx, likes) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    metrics = fn impressions ->
      %{
        "impression_count" => impressions,
        "like_count" => likes,
        "retweet_count" => 1,
        "quote_count" => 0,
        "reply_count" => 2,
        "bookmark_count" => 1
      }
    end

    [
      %{
        "id" => ctx.ids["video"],
        "text" => "Runners are here",
        "created_at" => now,
        "public_metrics" => metrics.(1000),
        "attachments" => %{"media_keys" => ["m1"]}
      },
      %{
        "id" => ctx.ids["thread"],
        "text" => "Why we built a cache 🧵",
        "created_at" => now,
        "public_metrics" => metrics.(400),
        "conversation_id" => ctx.ids["thread"]
      },
      # Self-reply: folded into the thread root, not a row of its own.
      %{
        "id" => ctx.ids["child"],
        "text" => "2/ details",
        "created_at" => now,
        "public_metrics" => metrics.(50),
        "conversation_id" => ctx.ids["thread"],
        "in_reply_to_user_id" => ctx.account_id
      },
      # Reply to someone else: not one of the account's posts.
      %{
        "id" => ctx.ids["reply"],
        "text" => "@someone thanks!",
        "created_at" => now,
        "public_metrics" => metrics.(30),
        "conversation_id" => "999",
        "in_reply_to_user_id" => "other"
      },
      # X sometimes omits in_reply_to_user_id on replies; the reference still marks it.
      %{
        "id" => ctx.ids["mention"],
        "text" => "@someone glad it works",
        "created_at" => now,
        "public_metrics" => metrics.(12),
        "conversation_id" => "998",
        "referenced_tweets" => [%{"type" => "replied_to", "id" => "998"}]
      },
      %{
        "id" => ctx.ids["link"],
        "text" => "Docs: https://tuist.dev/docs",
        "created_at" => now,
        "public_metrics" => metrics.(0),
        "non_public_metrics" => %{"url_link_clicks" => 7, "user_profile_clicks" => 3}
      }
    ]
  end

  defp stub_x(ctx, likes) do
    stub(Req, :request, fn opts ->
      assert opts[:auth] == {:bearer, "x-access"}

      body =
        if String.ends_with?(opts[:url], "/users/me") do
          %{"data" => %{"id" => ctx.account_id, "username" => ctx.username}}
        else
          # One read covers the last 14 days, clicks included.
          assert opts[:params][:"tweet.fields"] =~ "non_public_metrics"
          {:ok, start_time, _} = DateTime.from_iso8601(opts[:params][:start_time])
          assert_in_delta DateTime.diff(DateTime.utc_now(), start_time, :day), 14, 1

          %{
            "data" => posts(ctx, likes),
            "includes" => %{"media" => [%{"media_key" => "m1", "type" => "video"}]},
            "meta" => %{}
          }
        end

      {:ok, %Req.Response{status: 200, body: body}}
    end)
  end

  test "stores the account's own posts with format, thread and click metrics", ctx do
    stub_x(ctx, 5)
    assert {:ok, 3} = SocialPosts.sync_x(ctx.user)

    by_id = SocialPost |> where(account_id: ^ctx.account_id) |> Repo.all() |> Map.new(&{&1.external_id, &1})
    assert Map.keys(by_id) |> Enum.sort() == Enum.sort([ctx.ids["video"], ctx.ids["thread"], ctx.ids["link"]])

    assert %{format: "video", thread: false, impressions: 1000} = by_id[ctx.ids["video"]]
    assert %{format: "text", thread: true} = by_id[ctx.ids["thread"]]
    assert %{format: "link", url_clicks: 7, profile_clicks: 3} = by_id[ctx.ids["link"]]
    assert by_id[ctx.ids["video"]].url_clicks == nil
    assert by_id[ctx.ids["link"]].url == "https://x.com/#{ctx.username}/status/#{ctx.ids["link"]}"

    # 5 likes + 1 repost + 2 replies + 1 bookmark over 1000 impressions; no rate without impressions.
    assert SocialPost.engagements(by_id[ctx.ids["video"]]) == 9
    assert SocialPost.engagement_rate(by_id[ctx.ids["video"]]) == 0.009
    assert SocialPost.engagement_rate(by_id[ctx.ids["link"]]) == nil
  end

  test "a second sync on the same day updates that day's snapshot instead of adding one", ctx do
    stub_x(ctx, 5)
    {:ok, _} = SocialPosts.sync_x(ctx.user)
    stub_x(ctx, 8)
    {:ok, _} = SocialPosts.sync_x(ctx.user)

    post = Repo.get_by!(SocialPost, platform: "x", external_id: ctx.ids["video"])
    assert post.likes == 8
    assert [%SocialPostSnapshot{likes: 8}] = Repo.all(from s in SocialPostSnapshot, where: s.social_post_id == ^post.id)
  end

  test "the on-demand sync tool syncs the caller's account and reports X's reason when X rejects it", ctx do
    stub_x(ctx, 5)
    assert {:ok, %{posts: 3}} = SyncMySocialPosts.execute(mcp_conn(ctx.user), %{})

    stub(Req, :request, fn _opts ->
      {:ok, %Req.Response{status: 402, body: %{"title" => "CreditsDepleted", "detail" => "Add credits to continue."}}}
    end)

    assert {:error, message} = SyncMySocialPosts.execute(mcp_conn(ctx.user), %{})
    assert message =~ "402"
    assert message =~ "Add credits to continue."
  end

  test "summaries use medians per account and label threads separately", ctx do
    stub_x(ctx, 5)
    {:ok, _} = SocialPosts.sync_x(ctx.user)

    summary = SocialPosts.summarize(SocialPosts.list_posts(account: "@" <> ctx.username))

    assert [%{group: handle, posts: 3, median_impressions: 400}] = summary.by_account
    assert handle == "@" <> ctx.username
    assert summary.by_format |> Enum.map(& &1.group) |> Enum.sort() == ["link", "text thread", "video"]
  end
end
