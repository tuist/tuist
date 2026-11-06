defmodule TuistWeb.Plugs.MarkdownNegotiationPlug do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  alias Tuist.Docs
  alias TuistWeb.Marketing.Localization
  alias TuistWeb.Utilities.HtmlToMarkdown
  alias TuistWeb.Utilities.MarkdownResponse
  alias TuistWeb.Utilities.MarketingMarkdown

  @accept_header "accept"
  @markdown_content_type "text/markdown"
  @markdown_request_private_key :markdown_request
  @default_request_state %{requested?: false, override: nil}

  def init(opts), do: opts

  def call(%Plug.Conn{method: method} = conn, _opts) when method in ["GET", "HEAD"] do
    conn
    |> put_private(@markdown_request_private_key, build_request_state(conn))
    |> maybe_rewrite_accept_header()
    |> register_before_send(&negotiate_response/1)
  end

  def call(conn, _opts), do: conn

  defp build_request_state(conn) do
    if markdown_requested?(conn) do
      %{requested?: true, override: markdown_override(conn.request_path)}
    else
      @default_request_state
    end
  end

  defp markdown_requested?(conn) do
    media_types =
      conn
      |> get_req_header(@accept_header)
      |> Enum.flat_map(&String.split(&1, ","))
      |> Enum.map(&media_type_preference/1)

    markdown_quality = preferred_quality(media_types, @markdown_content_type)
    html_quality = preferred_quality(media_types, "text/html", true)

    markdown_quality > 0 and markdown_quality >= html_quality
  end

  defp media_type_preference(value) do
    case Plug.Conn.Utils.media_type(String.downcase(String.trim(value))) do
      {:ok, type, subtype, params} ->
        quality =
          case Float.parse(Map.get(params, "q", "1")) do
            {quality, ""} when quality >= 0 and quality <= 1 -> quality
            _ -> 0.0
          end

        {type <> "/" <> subtype, quality}

      :error ->
        {nil, 0.0}
    end
  end

  defp preferred_quality(media_types, type, wildcards? \\ false) do
    candidates = if wildcards?, do: [type, "text/*", "*/*"], else: [type]

    Enum.find_value(candidates, 0.0, fn candidate ->
      case for({media_type, quality} <- media_types, media_type == candidate, do: quality) do
        [] -> nil
        qualities -> Enum.max(qualities)
      end
    end)
  end

  defp maybe_rewrite_accept_header(conn) do
    if request_state(conn).requested? do
      rewrite_accept_header_to_html(conn)
    else
      conn
    end
  end

  defp rewrite_accept_header_to_html(conn) do
    html_accept_header = {"accept", "text/html"}

    req_headers =
      conn.req_headers
      |> Enum.reject(fn {header, _value} -> header == @accept_header end)
      |> List.insert_at(0, html_accept_header)

    %{conn | req_headers: req_headers}
  end

  defp negotiate_response(conn) do
    conn
    |> maybe_convert_to_markdown()
    |> put_marketing_alternate_link()
    |> MarkdownResponse.put_vary_accept()
  end

  defp put_marketing_alternate_link(conn) do
    case {conn.status, MarketingMarkdown.alternate_path(conn.request_path)} do
      {200, path} when is_binary(path) ->
        alternate = ~s(<#{path}>; rel="alternate"; type="text/markdown"; hreflang="en")
        links = get_resp_header(conn, "link") ++ [alternate]
        put_resp_header(conn, "link", Enum.join(links, ", "))

      _ ->
        conn
    end
  end

  defp maybe_convert_to_markdown(conn) do
    case markdown_body(conn) do
      {:ok, markdown} ->
        conn =
          if MarketingMarkdown.alternate_path(conn.request_path),
            do: put_resp_header(conn, "content-language", "en"),
            else: conn

        # Cloudflare does not generally partition its cache by Vary: Accept.
        # Never cache Markdown under an HTML URL; leave HTML caching unchanged.
        conn
        |> MarkdownResponse.prepare(markdown)
        |> put_resp_header("cloudflare-cdn-cache-control", "no-store")

      :error ->
        conn
    end
  end

  defp markdown_body(conn) do
    request_state = request_state(conn)

    cond do
      not request_state.requested? or conn.status != 200 ->
        :error

      is_binary(request_state.override) and request_state.override != "" ->
        {:ok, request_state.override}

      html_response?(conn) ->
        {:ok, html_response_to_markdown(conn)}

      true ->
        :error
    end
  end

  defp request_state(conn) do
    Map.get(conn.private, @markdown_request_private_key, @default_request_state)
  end

  defp html_response?(conn) do
    match?([<<"text/html", _::binary>> | _], get_resp_header(conn, "content-type"))
  end

  defp html_response_to_markdown(conn) do
    conn.resp_body
    |> IO.iodata_to_binary()
    |> HtmlToMarkdown.convert(request_url: current_request_url(conn))
  end

  defp current_request_url(conn) do
    URI.to_string(%URI{
      scheme: Atom.to_string(conn.scheme),
      host: conn.host,
      port: conn.port,
      path: conn.request_path,
      query: blank_to_nil(conn.query_string)
    })
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp markdown_override(request_path) do
    case String.split(request_path, "/", trim: true) do
      [locale, "docs" | path_segments] ->
        if locale in Localization.all_locales() do
          case Docs.get_page(locale, path_segments) do
            %{markdown: markdown} when is_binary(markdown) and markdown != "" -> markdown
            _ -> nil
          end
        end

      _ ->
        MarketingMarkdown.get(request_path)
    end
  end
end
