defmodule Atlas.GTM.SocialPosts do
  @moduledoc """
  Tracks how posts on connected social accounts perform.

  Accounts are held by Atlas (`Atlas.GTM.SocialAccounts`), not by people. A
  daily sync reads each account's recent posts with its own token, stores the
  latest metrics on `social_posts` and one `social_post_snapshots` row per post
  and day. Tokens never leave `Atlas.GTM.SocialAccounts`.
  """

  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.GTM.LinkedIn
  alias Atlas.GTM.SocialAccount
  alias Atlas.GTM.SocialAccounts
  alias Atlas.GTM.SocialPost
  alias Atlas.GTM.SocialPostSnapshot
  alias Atlas.Repo

  @api "https://api.x.com/2"
  # Posts gain nearly all their engagement in the first two weeks; older posts
  # keep the numbers of their last sync. X returns clicks for 30 days, so one
  # read covers both public and non-public metrics.
  @window_days 14
  @max_pages 10

  @doc "Posts from the last `days` days, newest first."
  def list_posts(opts \\ []) do
    since = DateTime.add(DateTime.utc_now(), -Keyword.get(opts, :days, 90) * 86_400, :second)

    SocialPost
    |> join(:left, [p], a in SocialAccount, on: a.platform == p.platform and a.external_id == p.account_id)
    |> select_merge([_p, a], %{kind: a.kind})
    |> where([p], p.posted_at >= ^since)
    |> maybe_account(Keyword.get(opts, :account))
    |> order_by([p], desc: p.posted_at)
    |> limit(^Keyword.get(opts, :limit, 500))
    |> Repo.all()
  end

  defp maybe_account(query, nil), do: query
  defp maybe_account(query, handle), do: where(query, [p], p.account_handle == ^handle)

  @doc """
  Median impressions, engagements and engagement rate per account kind (brand
  or personal), per account and per format, for posts in `posts`. Medians, because a single launch post would
  otherwise dominate an average.
  """
  def summarize(posts) do
    %{
      by_kind: group_summary(posts, &(&1.kind || "disconnected")),
      by_account: group_summary(posts, & &1.account_handle),
      by_format: group_summary(posts, &format_label/1)
    }
  end

  def format_label(%SocialPost{format: format, thread: true}), do: format <> " thread"
  def format_label(%SocialPost{format: format}), do: format

  defp group_summary(posts, key) do
    posts
    |> Enum.group_by(key)
    |> Enum.map(fn {group, group_posts} ->
      %{
        group: group,
        posts: length(group_posts),
        median_impressions: median(Enum.map(group_posts, & &1.impressions)),
        median_engagements: median(Enum.map(group_posts, &SocialPost.engagements/1)),
        median_engagement_rate:
          group_posts |> Enum.map(&SocialPost.engagement_rate/1) |> Enum.reject(&is_nil/1) |> median()
      }
    end)
    |> Enum.sort_by(& &1.posts, :desc)
  end

  defp median([]), do: nil

  defp median(values) do
    sorted = Enum.sort(values)
    count = length(sorted)
    middle = div(count, 2)

    if rem(count, 2) == 1,
      do: Enum.at(sorted, middle),
      else: (Enum.at(sorted, middle - 1) + Enum.at(sorted, middle)) / 2
  end

  @doc """
  Syncs every connected social account and prunes LinkedIn data past
  LinkedIn's storage limits. Returns the number of accounts synced.
  """
  def sync_all do
    synced =
      from(a in SocialAccount, where: not a.needs_authorization)
      |> Repo.all()
      |> Enum.count(&match?({:ok, _}, sync_account(&1)))

    prune_linkedin()
    synced
  end

  @doc """
  LinkedIn's API terms allow keeping a Page's own post content for six months
  and its reporting data for a year: older posts lose their text, and posts
  past a year are deleted with their snapshots.
  """
  def prune_linkedin(now \\ DateTime.utc_now()) do
    Repo.delete_all(
      from p in SocialPost, where: p.platform == "linkedin" and p.posted_at < ^DateTime.add(now, -365, :day)
    )

    Repo.update_all(
      from(p in SocialPost,
        where: p.platform == "linkedin" and p.posted_at < ^DateTime.add(now, -182, :day) and p.text != ""
      ),
      set: [text: ""]
    )

    :ok
  end

  @doc "Reads one account's recent posts and stores today's metrics."
  def sync_account(%SocialAccount{} = account, opts \\ []) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    with {:ok, rows} <- fetch_rows(account, DateTime.add(now, -@window_days * 86_400, :second), now) do
      Enum.each(rows, &store(&1, DateTime.to_date(now)))
      SocialAccounts.mark_synced(account)

      Audit.record(
        "social_posts.synced",
        %{
          target_type: "social_account",
          target_id: account.id,
          target_label: account.handle,
          metadata: %{
            "platform" => account.platform,
            "posts" => length(rows),
            "dashboard_path" => "/commercial/gtm/social/performance"
          }
        },
        Keyword.take(opts, [:actor, :interface]) |> Keyword.put_new(:interface, "worker")
      )

      {:ok, length(rows)}
    end
  end

  defp fetch_rows(%SocialAccount{platform: "linkedin"} = account, since, now) do
    SocialAccounts.with_token(account, &LinkedIn.rows(&1, account.external_id, account.handle, since, now))
  end

  defp fetch_rows(account, since, now) do
    with {:ok, me} <- SocialAccounts.with_token(account, &get(&1, "/users/me", [])),
         %{"id" => account_id, "username" => username} <- me["data"] || {:error, :invalid_response},
         {:ok, posts} <- fetch(account, account_id, since) do
      {:ok, build_rows(posts, account_id, username, now)}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_response}
    end
  end

  # Own posts including self-replies (so threads can be detected), excluding reposts.
  defp fetch(account, account_id, start_time) do
    fields =
      ~w(created_at public_metrics non_public_metrics attachments referenced_tweets conversation_id in_reply_to_user_id)

    params = [
      max_results: 100,
      exclude: "retweets",
      start_time: DateTime.to_iso8601(start_time),
      "tweet.fields": Enum.join(fields, ","),
      expansions: "attachments.media_keys",
      "media.fields": "type"
    ]

    paginate(account, "/users/#{account_id}/tweets", params, nil, [], [], 0)
  end

  defp paginate(_account, _path, _params, _token, posts, media, @max_pages), do: {:ok, attach_media(posts, media)}

  defp paginate(account, path, params, page_token, posts, media, page) do
    params = if page_token, do: Keyword.put(params, :pagination_token, page_token), else: params

    with {:ok, body} <- SocialAccounts.with_token(account, &get(&1, path, params)) do
      posts = posts ++ (body["data"] || [])
      media = media ++ (get_in(body, ["includes", "media"]) || [])

      case get_in(body, ["meta", "next_token"]) do
        next when is_binary(next) -> paginate(account, path, params, next, posts, media, page + 1)
        _ -> {:ok, attach_media(posts, media)}
      end
    end
  end

  defp attach_media(posts, media) do
    types = Map.new(media, &{&1["media_key"], &1["type"]})

    Enum.map(posts, fn post ->
      keys = get_in(post, ["attachments", "media_keys"]) || []
      Map.put(post, "media_types", Enum.map(keys, &types[&1]))
    end)
  end

  @doc false
  # Replies to other accounts are dropped; self-replies mark their root as a
  # thread and are otherwise folded into it. X sometimes omits
  # `in_reply_to_user_id` on replies, so a `replied_to` reference also marks one.
  def build_rows(posts, account_id, username, now) do
    thread_roots =
      for post <- posts, post["in_reply_to_user_id"] == account_id, into: MapSet.new(), do: post["conversation_id"]

    for post <- posts, not reply?(post) do
      post
      |> row(account_id, username, post["non_public_metrics"] || %{}, now)
      |> Map.put(:thread, MapSet.member?(thread_roots, post["id"]))
    end
  end

  defp reply?(post) do
    post["in_reply_to_user_id"] != nil or Enum.any?(post["referenced_tweets"] || [], &(&1["type"] == "replied_to"))
  end

  defp row(post, account_id, username, private, now) do
    metrics = post["public_metrics"] || %{}
    {:ok, posted_at, _} = DateTime.from_iso8601(post["created_at"])

    %{
      platform: "x",
      external_id: post["id"],
      account_id: account_id,
      account_handle: "@" <> username,
      url: "https://x.com/#{username}/status/#{post["id"]}",
      text: post["text"] || "",
      format: format(post),
      posted_at: DateTime.truncate(posted_at, :second),
      impressions: metrics["impression_count"] || 0,
      likes: metrics["like_count"] || 0,
      reposts: metrics["retweet_count"] || 0,
      quotes: metrics["quote_count"] || 0,
      replies: metrics["reply_count"] || 0,
      bookmarks: metrics["bookmark_count"] || 0,
      url_clicks: private["url_link_clicks"],
      profile_clicks: private["user_profile_clicks"],
      metrics_updated_at: now
    }
  end

  defp format(post) do
    media = post["media_types"] || []
    referenced = Enum.map(post["referenced_tweets"] || [], & &1["type"])

    cond do
      Enum.any?(media, &(&1 in ["video", "animated_gif"])) -> "video"
      "photo" in media -> "image"
      "quoted" in referenced -> "quote"
      Regex.match?(~r{https?://}, post["text"] || "") -> "link"
      true -> "text"
    end
  end

  # Clicks stay at their last known value once a post ages out of X's 30-day window.
  defp store(row, today) do
    Repo.transaction(fn ->
      existing = Repo.get_by(SocialPost, platform: row.platform, external_id: row.external_id)

      row =
        if existing,
          do: %{
            row
            | url_clicks: row.url_clicks || existing.url_clicks,
              profile_clicks: row.profile_clicks || existing.profile_clicks
          },
          else: row

      post =
        (existing || %SocialPost{})
        |> Ecto.Changeset.change(row)
        |> Repo.insert_or_update!()

      snapshot = Map.take(row, SocialPost.metrics())

      %SocialPostSnapshot{social_post_id: post.id, captured_on: today}
      |> Ecto.Changeset.change(snapshot)
      |> Repo.insert!(
        on_conflict: {:replace, SocialPost.metrics() ++ [:updated_at]},
        conflict_target: [:social_post_id, :captured_on]
      )
    end)
  end

  defp get(token, path, params) do
    case Req.request(method: :get, url: @api <> path, params: params, auth: {:bearer, token}, retry: false) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) -> {:ok, body}
      {:ok, %Req.Response{status: 429}} -> {:error, :rate_limited}
      {:ok, %Req.Response{status: status, body: body}} -> {:error, {:http, status, error_detail(body)}}
      _ -> {:error, :provider_unavailable}
    end
  end

  # X explains rejections such as missing credits in `title` and `detail`.
  defp error_detail(%{} = body), do: body |> Map.take(["title", "detail"]) |> Map.values() |> Enum.join(": ")
  defp error_detail(_body), do: nil
end
