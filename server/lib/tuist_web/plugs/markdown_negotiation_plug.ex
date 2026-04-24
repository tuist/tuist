defmodule TuistWeb.Plugs.MarkdownNegotiationPlug do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  alias TuistWeb.DocsMarkdown
  alias TuistWeb.Utilities.HtmlToMarkdown
  alias TuistWeb.Utilities.MarkdownResponse

  @accept_header "accept"
  @markdown_content_type "text/markdown"
  @markdown_private_key :markdown_requested
  @markdown_override_private_key :markdown_override

  def init(opts), do: opts

  def call(%Plug.Conn{method: method} = conn, _opts) when method in ["GET", "HEAD"] do
    markdown_requested? = markdown_requested?(conn)
    markdown_override = markdown_override(conn, markdown_requested?)

    conn
    |> put_private(@markdown_private_key, markdown_requested?)
    |> put_private(@markdown_override_private_key, markdown_override)
    |> maybe_rewrite_accept_header(markdown_requested?)
    |> register_before_send(&negotiate_response/1)
  end

  def call(conn, _opts), do: conn

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

  defp maybe_rewrite_accept_header(conn, false), do: conn

  defp maybe_rewrite_accept_header(conn, true) do
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
    |> ensure_vary_accept()
  end

  defp maybe_convert_to_markdown(
         %Plug.Conn{private: %{@markdown_private_key => true, @markdown_override_private_key => markdown}} = conn
       )
       when is_binary(markdown) and markdown != "" do
    MarkdownResponse.prepare(conn, markdown, vary_accept: true)
  end

  defp maybe_convert_to_markdown(%Plug.Conn{private: %{@markdown_private_key => true}} = conn) do
    case get_resp_header(conn, "content-type") do
      [<<"text/html", _::binary>> | _] ->
        markdown =
          conn.resp_body
          |> IO.iodata_to_binary()
          |> HtmlToMarkdown.convert(request_url: current_request_url(conn))

        MarkdownResponse.prepare(conn, markdown, vary_accept: true)

      _ ->
        conn
    end
  end

  defp maybe_convert_to_markdown(conn), do: conn

  defp ensure_vary_accept(conn) do
    vary =
      conn
      |> get_resp_header("vary")
      |> List.first()
      |> to_vary_values()

    if Enum.any?(vary, &(String.downcase(&1) == @accept_header)) do
      conn
    else
      put_resp_header(conn, "vary", Enum.join(vary ++ ["Accept"], ", "))
    end
  end

  defp to_vary_values(nil), do: []

  defp to_vary_values(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
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

  defp markdown_override(conn, true) do
    case DocsMarkdown.from_request_path(conn.request_path) do
      {:ok, markdown} -> markdown
      :error -> :error
    end
  end

  defp markdown_override(_conn, false), do: :error
end
