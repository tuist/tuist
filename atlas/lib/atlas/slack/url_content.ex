defmodule Atlas.Slack.URLContent do
  @moduledoc false

  use Condukt.Tool

  alias Atlas.HTTP
  alias Atlas.URL, as: AtlasURL

  @accept_header [
    {"accept",
     "text/html, text/plain;q=0.9, text/markdown;q=0.9, application/json;q=0.8, application/xml;q=0.7, text/xml;q=0.7"}
  ]
  @max_redirects 3
  @max_content_chars 12_000
  @request_timeout 10_000

  @impl true
  def name, do: "fetch_url_content"

  @impl true
  def description do
    """
    Fetch and read the text content of a public URL. Use this when a reply
    depends on the contents of a linked page or document. This only supports
    public HTML, plain text, markdown, XML, and JSON resources.
    """
  end

  @impl true
  def parameters do
    %{
      type: "object",
      required: ["url"],
      properties: %{
        url: %{type: "string", minLength: 1, description: "The public http or https URL to read."}
      }
    }
  end

  @impl true
  def call(%{"url" => url}, _context) do
    fetch(url)
  end

  def fetch(url) when is_binary(url) do
    with {:ok, uri} <- AtlasURL.validate_public(url),
         {:ok, final_uri, response, redirect_count} <- request(uri, @max_redirects) do
      normalize_response(final_uri, response, redirect_count)
    end
  end

  def fetch(_url), do: {:error, "Provide a valid http or https URL."}

  defp request(uri, redirects_left) do
    req =
      HTTP.req_default_options()
      |> Keyword.merge(
        url: URI.to_string(uri),
        headers: @accept_header,
        receive_timeout: @request_timeout,
        max_redirects: 0,
        redirect: false,
        retry: false
      )
      |> Req.new()

    case Req.run(req) do
      {final_req, %Req.Response{} = response} ->
        follow_response(final_req.url, response, redirects_left)

      {_req, exception} ->
        {:error, format_request_error(exception)}
    end
  end

  defp follow_response(url, %Req.Response{status: status} = response, redirects_left)
       when status in [301, 302, 303, 307, 308] do
    if redirects_left <= 0 do
      {:error, "Too many redirects while fetching #{URI.to_string(url)}."}
    else
      with [location | _] <- Req.Response.get_header(response, "location"),
           next_url = URI.merge(url, location),
           {:ok, next_uri} <- AtlasURL.validate_public(URI.to_string(next_url)) do
        request(next_uri, redirects_left - 1)
      else
        [] ->
          {:error, "The URL redirected without a location header."}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp follow_response(url, %Req.Response{} = response, redirects_left) do
    {:ok, url, response, @max_redirects - redirects_left}
  end

  defp normalize_response(final_uri, %Req.Response{status: status} = response, redirect_count)
       when status >= 200 and status < 300 do
    content_type = normalized_content_type(response)

    with {:ok, title, content} <- extract_content(response, content_type) do
      {content, truncated?} = truncate_content(content)

      {:ok,
       %{
         final_url: URI.to_string(final_uri),
         content_type: content_type || "unknown",
         title: blank_to_nil(title),
         content: content,
         truncated: truncated?,
         redirects_followed: redirect_count
       }}
    end
  end

  defp normalize_response(final_uri, %Req.Response{status: status}, _redirect_count) do
    {:error, "Received HTTP #{status} while fetching #{URI.to_string(final_uri)}."}
  end

  defp extract_content(%Req.Response{body: body}, content_type) when content_type in [nil, "text/plain"] do
    content =
      case body do
        binary when is_binary(binary) -> normalize_plain_text(binary)
        other -> other |> inspect(pretty: true) |> normalize_plain_text()
      end

    readable_result(nil, content)
  end

  defp extract_content(%Req.Response{body: body}, content_type)
       when content_type in ["text/markdown", "text/x-markdown", "application/xml", "text/xml"] do
    content =
      case body do
        binary when is_binary(binary) -> normalize_plain_text(binary)
        other -> other |> inspect(pretty: true) |> normalize_plain_text()
      end

    readable_result(nil, content)
  end

  defp extract_content(%Req.Response{body: body}, content_type)
       when content_type in ["text/html", "application/xhtml+xml"] do
    html =
      case body do
        binary when is_binary(binary) -> binary
        other -> to_string(other)
      end

    {title, content} = extract_html(html)
    readable_result(title, content)
  end

  defp extract_content(%Req.Response{body: body}, "application/json") do
    content =
      case Jason.encode(body, pretty: true) do
        {:ok, json} -> normalize_plain_text(json)
        {:error, _reason} -> body |> inspect(pretty: true) |> normalize_plain_text()
      end

    readable_result(nil, content)
  end

  defp extract_content(_response, nil) do
    {:error, "The URL did not return a supported text content type."}
  end

  defp extract_content(_response, content_type) do
    {:error,
     "Unsupported content type #{content_type}. Only public HTML, plain text, markdown, XML, and JSON are supported."}
  end

  defp readable_result(title, content) do
    case blank_to_nil(content) do
      nil -> {:error, "The URL did not contain readable text content."}
      readable -> {:ok, title, readable}
    end
  end

  defp extract_html(html) do
    title =
      Regex.run(~r/<title\b[^>]*>(.*?)<\/title>/is, html, capture: :all_but_first)
      |> List.first()
      |> decode_html_entities()
      |> normalize_inline_text()

    content =
      html
      |> strip_tag_contents("script")
      |> strip_tag_contents("style")
      |> strip_tag_contents("noscript")
      |> then(&Regex.replace(~r/<li\b[^>]*>/i, &1, "\n- "))
      |> then(&Regex.replace(~r/<br\s*\/?>/i, &1, "\n"))
      |> then(
        &Regex.replace(
          ~r/<\/(p|div|section|article|aside|header|footer|nav|tr|table|ul|ol|h[1-6])>/i,
          &1,
          "\n"
        )
      )
      |> then(&Regex.replace(~r/<!--.*?-->/s, &1, ""))
      |> then(&Regex.replace(~r/<[^>]+>/, &1, " "))
      |> decode_html_entities()
      |> normalize_plain_text()

    {title, content}
  end

  defp strip_tag_contents(html, tag) do
    Regex.replace(~r/<#{tag}\b[^>]*>.*?<\/#{tag}>/is, html, "")
  end

  defp truncate_content(content) when is_binary(content) do
    truncated? = String.length(content) > @max_content_chars
    {String.slice(content, 0, @max_content_chars), truncated?}
  end

  defp normalized_content_type(response) do
    response
    |> Req.Response.get_header("content-type")
    |> List.first()
    |> case do
      nil -> nil
      value -> value |> String.downcase() |> String.split(";", parts: 2) |> List.first() |> String.trim()
    end
  end

  defp normalize_plain_text(text) when is_binary(text) do
    text
    |> String.replace("\r\n", "\n")
    |> String.replace("\r", "\n")
    |> String.replace("\u00A0", " ")
    |> String.split("\n")
    |> Enum.map(&normalize_inline_text/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
    |> String.trim()
  end

  defp normalize_inline_text(nil), do: nil

  defp normalize_inline_text(text) when is_binary(text) do
    text
    |> String.replace(~r/\s+/u, " ")
    |> String.replace(~r/\s+([.,;:!?])/u, "\\1")
    |> String.trim()
    |> blank_to_nil()
  end

  defp decode_html_entities(nil), do: nil

  defp decode_html_entities(text) when is_binary(text) do
    text
    |> decode_numeric_entities(~r/&#(\d+);/, 10)
    |> decode_numeric_entities(~r/&#x([0-9a-fA-F]+);/, 16)
    |> String.replace("&nbsp;", " ")
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
  end

  defp decode_numeric_entities(text, regex, base) do
    Regex.replace(regex, text, fn _match, codepoint ->
      codepoint
      |> String.to_integer(base)
      |> maybe_codepoint()
    end)
  end

  defp maybe_codepoint(codepoint) when codepoint in 0..0x10FFFF do
    <<codepoint::utf8>>
  rescue
    ArgumentError -> ""
  end

  defp maybe_codepoint(_codepoint), do: ""

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp format_request_error(%Req.TransportError{reason: reason}) do
    "Could not fetch the URL: #{inspect(reason)}."
  end

  defp format_request_error(%Req.HTTPError{} = exception) do
    "Could not fetch the URL: #{Exception.message(exception)}."
  end

  defp format_request_error(exception) when is_struct(exception) do
    "Could not fetch the URL: #{Exception.message(exception)}."
  end

  defp format_request_error(reason) do
    "Could not fetch the URL: #{inspect(reason)}."
  end
end
