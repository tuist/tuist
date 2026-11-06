defmodule Atlas.Moodboard.Preview do
  @moduledoc "Passive link metadata discovery. Remote HTML and scripts are never rendered or executed."

  alias Atlas.Moodboard.SafeHTTP
  alias Atlas.Moodboard.Text

  @x_hosts ~w(x.com www.x.com mobile.x.com twitter.com www.twitter.com mobile.twitter.com m.twitter.com)
  @block_tags ~w(article main section div p br h1 h2 h3 h4 h5 h6 li ul ol blockquote pre)
  @ignored_tags ~w(script style noscript nav footer header aside iframe form svg)

  def fetch(url) do
    case x_post_id(url) do
      nil -> fetch_page(url)
      id -> fetch_x_post(id)
    end
  rescue
    _ -> {:error, :unavailable}
  end

  defp fetch_page(url) do
    with {:ok, %{status: status} = response} <- SafeHTTP.fetch(url),
         true <- status in 200..299 do
      type = content_type(response.headers)

      cond do
        type in ["image/jpeg", "image/png", "image/webp", "image/gif", "image/avif"] ->
          {:ok, %{kind: "image", preview_image_url: response.url}}

        type in ["video/mp4", "video/webm"] ->
          {:ok, %{kind: "video", preview_video_url: response.url}}

        type in ["text/html", "application/xhtml+xml"] ->
          {:ok, from_html(response.body, response.url)}

        type == "text/plain" ->
          {:ok, %{kind: "article", source_text: text_content(response.body)}}

        true ->
          {:error, :unsupported_content}
      end
    else
      _ -> {:error, :unavailable}
    end
  end

  def from_html(html, url) do
    doc = LazyHTML.from_document(html)

    metadata = html_metadata(doc)
    image = media_url(first_value(metadata, ~w(og:image:secure_url og:image twitter:image twitter:image:src)), url)
    article? = metadata["og:type"] == "article" or Enum.any?(LazyHTML.query(doc, "article"))
    video = metadata_video(metadata, url) || body_video(doc, url, image, article?)

    title =
      first_value(metadata, ~w(og:title twitter:title)) ||
        doc |> LazyHTML.query("head > title:first-of-type") |> LazyHTML.text()

    %{
      kind: html_kind(article?, video),
      source_title: bounded(title, 200),
      source_description: bounded(first_value(metadata, ~w(og:description description twitter:description)), 2000),
      source_text: readable_text(doc),
      preview_image_url: image,
      preview_video_url: video
    }
  end

  defp html_metadata(doc) do
    doc
    |> LazyHTML.query("meta")
    |> LazyHTML.attributes()
    |> Enum.reduce(%{}, fn attrs, acc ->
      attrs = Map.new(attrs)
      key = attrs["property"] || attrs["name"]

      if is_binary(key) and is_binary(attrs["content"]),
        do: Map.put_new(acc, String.downcase(key), attrs["content"]),
        else: acc
    end)
  end

  defp first_value(metadata, keys), do: Enum.find_value(keys, &metadata[&1])

  defp metadata_video(metadata, url) do
    if first_value(metadata, ~w(og:video:type twitter:player:stream:content_type)) in ["video/mp4", "video/webm"] do
      metadata |> first_value(~w(og:video:secure_url og:video:url og:video twitter:player:stream)) |> media_url(url)
    end
  end

  defp html_kind(true, _video), do: "article"
  defp html_kind(false, video) when is_binary(video), do: "video"
  defp html_kind(false, _video), do: "link"

  defp body_video(doc, url, nil, false), do: html_video(doc, url)
  defp body_video(_doc, _url, _image, _article?), do: nil

  defp html_video(doc, url) do
    doc
    |> LazyHTML.query("video[src], video source[src]")
    |> LazyHTML.attributes()
    |> Enum.find_value(fn attrs ->
      attrs = Map.new(attrs)
      source = attrs["src"]
      if attrs["type"] in ["video/mp4", "video/webm"] or video_extension?(source), do: media_url(source, url)
    end)
  end

  defp video_extension?(url) when is_binary(url), do: Path.extname(URI.parse(url).path || "") in [".mp4", ".webm"]
  defp video_extension?(_url), do: false

  defp readable_text(doc) do
    scope =
      Enum.find_value(["article", "main", "body"], fn selector ->
        selected = LazyHTML.query(doc, selector)
        if Enum.any?(selected), do: selected
      end) || doc

    scope |> LazyHTML.to_tree() |> tree_text() |> IO.iodata_to_binary() |> text_content()
  end

  defp tree_text(nodes) when is_list(nodes), do: Enum.map(nodes, &tree_text/1)
  defp tree_text(text) when is_binary(text), do: text
  defp tree_text({tag, _attrs, _children}) when tag in @ignored_tags, do: ""
  defp tree_text({tag, _attrs, children}) when tag in @block_tags, do: ["\n", tree_text(children), "\n"]
  defp tree_text({_tag, _attrs, children}), do: tree_text(children)
  defp tree_text(_node), do: ""

  defp fetch_x_post(id) do
    # This is X's public embed endpoint, not an authenticated API or a third-party proxy.
    url = "https://cdn.syndication.twimg.com/tweet-result?" <> URI.encode_query(%{id: id, lang: "en", token: "1"})

    with {:ok, %{status: 200, body: body}} <- SafeHTTP.fetch(url),
         {:ok, %{"id_str" => ^id} = post} <- Jason.decode(body) do
      {:ok, from_x_post(post)}
    else
      _ -> {:error, :unavailable}
    end
  end

  def from_x_post(post) do
    media =
      case post["mediaDetails"] do
        media when is_list(media) -> media
        _ -> []
      end

    video = Enum.find_value(media, &x_video/1)

    image = Enum.find_value(media, fn item -> media_url(item["media_url_https"], "https://x.com/") end)
    name = get_in(post, ["user", "name"]) || "X post"
    text = get_in(post, ["note_tweet", "text"]) || post["text"]

    %{
      kind: if(video, do: "video", else: if(image, do: "image", else: "article")),
      source_title: bounded(name <> " on X", 200),
      source_description: bounded(text, 2000),
      source_text: text_content(text),
      preview_image_url: image,
      preview_video_url: video
    }
  end

  defp x_video(%{"video_info" => %{"variants" => variants}}) when is_list(variants) do
    variants
    |> Enum.filter(&mp4_variant?/1)
    |> Enum.sort_by(&(&1["bitrate"] || 0))
    |> Enum.find_value(& &1["url"])
  end

  defp x_video(_media), do: nil

  defp mp4_variant?(variant) when is_map(variant),
    do: variant["content_type"] == "video/mp4" and SafeHTTP.public_url?(variant["url"])

  defp mp4_variant?(_variant), do: false

  defp x_post_id(url) do
    uri = URI.parse(url)

    if String.downcase(uri.host || "") in @x_hosts do
      case Regex.run(~r"^/(?:[^/]+|i/web)/status/([0-9]{1,25})(?:/(?:photo|video)/[0-9]+)?/?$", uri.path || "") do
        [_, id] -> id
        _ -> nil
      end
    end
  end

  defp media_url(value, base) when is_binary(value) do
    url = base |> URI.merge(String.trim(value)) |> URI.to_string()
    if SafeHTTP.public_url?(url), do: url
  rescue
    _ -> nil
  end

  defp media_url(_value, _base), do: nil

  defp text_content(value) when is_binary(value) do
    value
    |> Text.clean(100_000)
    |> String.replace(~r/[^\S\r\n]+/u, " ")
    |> String.split(~r/\r?\n/u)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
    |> String.slice(0, 20_000)
    |> case do
      "" -> nil
      text -> text
    end
  end

  defp text_content(_value), do: nil

  defp bounded(value, limit) when is_binary(value) do
    value
    |> Text.clean(100_000)
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> String.slice(0, limit)
    |> case do
      "" -> nil
      text -> text
    end
  end

  defp bounded(_value, _limit), do: nil

  defp content_type(headers) do
    case List.keyfind(headers, "content-type", 0) do
      {_, type} -> type |> String.split(";", parts: 2) |> hd() |> String.downcase() |> String.trim()
      _ -> ""
    end
  end
end
