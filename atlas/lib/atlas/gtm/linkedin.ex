defmodule Atlas.GTM.LinkedIn do
  @moduledoc """
  Reads a LinkedIn Page's own posts and their lifetime statistics through the
  Community Management API, for `Atlas.GTM.SocialPosts`.

  LinkedIn reports lifetime totals per post; the daily snapshots in
  `social_post_snapshots` are what turn them into growth over time.
  """

  @api "https://api.linkedin.com/rest"
  # Marketing API versions are monthly and sunset after a year.
  @version "202611"
  @max_pages 5
  @stats_batch 20

  @doc "The first LinkedIn Page the token's member administers, as `%{id, name}`."
  def administered_page(token) do
    params = [q: "roleAssignee", role: "ADMINISTRATOR", state: "APPROVED"]

    with {:ok, %{"elements" => [_ | _] = elements}} <- get(token, "/organizationAcls", params),
         "urn:li:organization:" <> id <- page_urn(hd(elements)),
         {:ok, page} <- get(token, "/organizations/#{id}", []) do
      {:ok, %{id: id, name: page["localizedName"] || page["vanityName"] || "LinkedIn page #{id}"}}
    else
      {:error, _} = error -> error
      _ -> {:error, :no_administered_page}
    end
  end

  defp page_urn(element), do: element["organization"] || element["organizationTarget"]

  @doc "Rows for `Atlas.GTM.SocialPosts` of the Page's posts published since `since`."
  def rows(token, page_id, page_name, since, now) do
    with {:ok, posts} <- posts(token, page_id, DateTime.to_unix(since, :millisecond), 0, []),
         {:ok, stats} <- statistics(token, page_id, Enum.map(posts, & &1["id"])) do
      {:ok, Enum.map(posts, &row(&1, stats[&1["id"]] || %{}, page_id, page_name, now))}
    end
  end

  # Newest first; stops at the first page that reaches posts older than `since`.
  defp posts(_token, _page_id, _since, @max_pages, acc), do: {:ok, acc}

  defp posts(token, page_id, since, page, acc) do
    query =
      "author=#{encode("urn:li:organization:#{page_id}")}&q=author&count=100&sortBy=CREATED&start=#{page * 100}"

    with {:ok, body} <- get(token, "/posts?" <> query) do
      elements = body["elements"] || []
      recent = Enum.filter(elements, &((&1["publishedAt"] || 0) >= since and &1["lifecycleState"] == "PUBLISHED"))
      acc = acc ++ recent

      if length(elements) < 100 or Enum.any?(elements, &((&1["publishedAt"] || 0) < since)),
        do: {:ok, acc},
        else: posts(token, page_id, since, page + 1, acc)
    end
  end

  # Posts without impressions or actions are left out of LinkedIn's answer; they count as zero.
  defp statistics(_token, _page_id, []), do: {:ok, %{}}

  defp statistics(token, page_id, urns) do
    urns
    |> Enum.chunk_every(@stats_batch)
    |> Enum.reduce_while({:ok, %{}}, fn batch, {:ok, acc} ->
      {shares, ugc_posts} = Enum.split_with(batch, &String.starts_with?(&1, "urn:li:share:"))

      query =
        Enum.join(
          ["q=organizationalEntity", "organizationalEntity=" <> encode("urn:li:organization:#{page_id}")] ++
            list_param("shares", shares) ++ list_param("ugcPosts", ugc_posts),
          "&"
        )

      case get(token, "/organizationalEntityShareStatistics?" <> query) do
        {:ok, body} ->
          stats = Map.new(body["elements"] || [], &{&1["share"] || &1["ugcPost"], &1["totalShareStatistics"] || %{}})
          {:cont, {:ok, Map.merge(acc, stats)}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp list_param(_name, []), do: []
  defp list_param(name, urns), do: ["#{name}=List(#{Enum.map_join(urns, ",", &encode/1)})"]

  defp row(post, stats, page_id, page_name, now) do
    %{
      platform: "linkedin",
      external_id: post["id"],
      account_id: page_id,
      account_handle: page_name,
      url: "https://www.linkedin.com/feed/update/#{post["id"]}/",
      text: post["commentary"] || "",
      format: format(post),
      thread: false,
      posted_at: post["publishedAt"] |> DateTime.from_unix!(:millisecond) |> DateTime.truncate(:second),
      impressions: stats["impressionCount"] || 0,
      likes: max(stats["likeCount"] || 0, 0),
      reposts: stats["shareCount"] || 0,
      quotes: 0,
      replies: stats["commentCount"] || 0,
      bookmarks: 0,
      url_clicks: stats["clickCount"] || 0,
      profile_clicks: nil,
      metrics_updated_at: now
    }
  end

  @doc false
  def format(post) do
    content = post["content"] || %{}

    cond do
      media = media_format(content) -> media
      post["reshareContext"] -> "quote"
      Map.has_key?(content, "article") or Regex.match?(~r{https?://}, post["commentary"] || "") -> "link"
      true -> "text"
    end
  end

  defp media_format(%{"multiImage" => _}), do: "image"

  defp media_format(%{"media" => %{"id" => "urn:li:video:" <> _}}), do: "video"
  defp media_format(%{"media" => %{"id" => "urn:li:image:" <> _}}), do: "image"
  defp media_format(_content), do: nil

  defp encode(urn), do: URI.encode_www_form(urn)

  defp get(token, path, params \\ []) do
    request = [
      method: :get,
      url: @api <> path,
      params: params,
      auth: {:bearer, token},
      headers: [{"linkedin-version", @version}, {"x-restli-protocol-version", "2.0.0"}],
      retry: false
    ]

    case Req.request(request) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) -> {:ok, body}
      {:ok, %Req.Response{status: 429}} -> {:error, :rate_limited}
      {:ok, %Req.Response{status: status, body: body}} -> {:error, {:http, status, error_detail(body)}}
      _ -> {:error, :provider_unavailable}
    end
  end

  defp error_detail(%{"message" => message}), do: message
  defp error_detail(_body), do: nil
end
