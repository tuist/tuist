defmodule TuistWeb.Plugs.MarkdownNegotiationPlug do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  alias Tuist.Docs
  alias TuistWeb.Marketing.Localization
  alias TuistWeb.Utilities.HtmlToMarkdown
  alias TuistWeb.Utilities.MarkdownResponse

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
    conn
    |> get_req_header(@accept_header)
    |> Enum.any?(fn value ->
      value
      |> String.downcase()
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.any?(&String.starts_with?(&1, @markdown_content_type))
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
    |> MarkdownResponse.put_vary_accept()
  end

  defp maybe_convert_to_markdown(conn) do
    case markdown_body(conn) do
      {:ok, markdown} ->
        MarkdownResponse.prepare(conn, markdown)

      :error ->
        conn
    end
  end

  defp markdown_body(conn) do
    request_state = request_state(conn)

    cond do
      not request_state.requested? ->
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
        else
          nil
        end

      _ ->
        nil
    end
  end
end
