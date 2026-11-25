defmodule Atlas.GTM.SocialPosts do
  @moduledoc """
  Tracks how posts on connected social accounts perform.

  Each person who connects X at /settings/connections contributes that
  account's posts. A daily sync reads them with the connection's own token,
  stores the latest metrics on `social_posts` and one `social_post_snapshots`
  row per post and day. The metrics are shared with everyone who can read GTM;
  tokens never leave `Atlas.Connections`.
  """

  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Connections
  alias Atlas.Connections.Connection
  alias Atlas.GTM.SocialPost
  alias Atlas.GTM.SocialPostSnapshot
  alias Atlas.Repo
  alias Atlas.Users

  @api "https://api.x.com/2"
  @scopes ["tweet.read"]
  # Public counters are read for this window; X returns click metrics only
  # for posts created in the last 30 days.
  @window_days 90
  @click_window_days 29
  @max_pages 10

  @doc "Posts from the last `days` days, newest first."
  def list_posts(opts \\ []) do
    since = DateTime.add(DateTime.utc_now(), -Keyword.get(opts, :days, 90) * 86_400, :second)

    SocialPost
    |> where([p], p.posted_at >= ^since)
    |> maybe_account(Keyword.get(opts, :account))
    |> order_by([p], desc: p.posted_at)
    |> limit(^Keyword.get(opts, :limit, 500))
    |> Repo.all()
  end

  defp maybe_account(query, nil), do: query
  defp maybe_account(query, handle), do: where(query, [p], p.account_handle == ^handle)

  @doc """
  Median impressions, engagements and engagement rate per account and per
  format, for posts in `posts`. Medians, because a single launch post would
  otherwise dominate an average.
  """
  def summarize(posts) do
    %{
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

  @doc "Syncs every connected X account. Returns the number of accounts synced."
  def sync_all do
    from(c in Connection, where: c.provider == "x" and not c.needs_authorization, select: c.user_id)
    |> Repo.all()
    |> Enum.count(fn user_id ->
      user_id
      |> Users.get_user()
      |> sync_x()
      |> case do
        {:ok, _count} -> true
        _ -> false
      end
    end)
  end

  @doc "Reads the connected X account's posts and stores today's metrics."
  def sync_x(nil), do: {:error, :not_connected}

  def sync_x(user) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    with {:ok, me} <- with_token(user, &get(&1, "/users/me", [])),
         %{"id" => account_id, "username" => username} <- me["data"] || {:error, :invalid_response},
         {:ok, posts} <- fetch(user, account_id, DateTime.add(now, -@window_days * 86_400, :second), false),
         {:ok, recent} <- fetch(user, account_id, DateTime.add(now, -@click_window_days * 86_400, :second), true) do
      clicks = Map.new(recent, &{&1["id"], &1["non_public_metrics"]})
      rows = build_rows(posts, account_id, username, clicks, now)
      Enum.each(rows, &store(&1, DateTime.to_date(now)))

      Audit.record(
        "social_posts.synced",
        %{
          target_type: "social_account",
          target_label: "@" <> username,
          metadata: %{
            "platform" => "x",
            "posts" => length(rows),
            "dashboard_path" => "/commercial/gtm/social/performance"
          }
        },
        actor: user,
        interface: "worker"
      )

      {:ok, length(rows)}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_response}
    end
  end

  # Own posts including self-replies (so threads can be detected), excluding reposts.
  defp fetch(user, account_id, start_time, clicks?) do
    fields = ~w(created_at public_metrics attachments referenced_tweets conversation_id in_reply_to_user_id)
    fields = if clicks?, do: ["non_public_metrics" | fields], else: fields

    params = [
      max_results: 100,
      exclude: "retweets",
      start_time: DateTime.to_iso8601(start_time),
      "tweet.fields": Enum.join(fields, ","),
      expansions: "attachments.media_keys",
      "media.fields": "type"
    ]

    paginate(user, "/users/#{account_id}/tweets", params, nil, [], [], 0)
  end

  defp paginate(_user, _path, _params, _token, posts, media, @max_pages), do: {:ok, attach_media(posts, media)}

  defp paginate(user, path, params, page_token, posts, media, page) do
    params = if page_token, do: Keyword.put(params, :pagination_token, page_token), else: params

    with {:ok, body} <- with_token(user, &get(&1, path, params)) do
      posts = posts ++ (body["data"] || [])
      media = media ++ (get_in(body, ["includes", "media"]) || [])

      case get_in(body, ["meta", "next_token"]) do
        next when is_binary(next) -> paginate(user, path, params, next, posts, media, page + 1)
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
  # thread and are otherwise folded into it.
  def build_rows(posts, account_id, username, clicks, now) do
    thread_roots =
      for post <- posts, post["in_reply_to_user_id"] == account_id, into: MapSet.new(), do: post["conversation_id"]

    for post <- posts, is_nil(post["in_reply_to_user_id"]) do
      post
      |> row(account_id, username, clicks[post["id"]] || %{}, now)
      |> Map.put(:thread, MapSet.member?(thread_roots, post["id"]))
    end
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

  defp with_token(user, fun) do
    with {:ok, token} <- Connections.access_token(user, "x", @scopes) do
      case fun.(token) do
        {:error, {:http, 401}} ->
          with {:ok, refreshed} <- Connections.refresh_access_token(user, "x", @scopes, token), do: fun.(refreshed)

        result ->
          result
      end
    end
  end

  defp get(token, path, params) do
    case Req.request(method: :get, url: @api <> path, params: params, auth: {:bearer, token}, retry: false) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) -> {:ok, body}
      {:ok, %Req.Response{status: 429}} -> {:error, :rate_limited}
      {:ok, %Req.Response{status: status}} -> {:error, {:http, status}}
      _ -> {:error, :provider_unavailable}
    end
  end
end
