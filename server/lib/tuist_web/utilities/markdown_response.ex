defmodule TuistWeb.Utilities.MarkdownResponse do
  @moduledoc false

  import Plug.Conn

  @accept_header "accept"
  @markdown_content_type "text/markdown"

  def prepare(conn, markdown, opts \\ []) when is_binary(markdown) do
    conn
    |> maybe_put_vary_accept(Keyword.get(opts, :vary_accept, false))
    |> delete_resp_header("content-length")
    |> put_resp_header("x-markdown-tokens", Integer.to_string(token_estimate(markdown)))
    |> put_resp_content_type(@markdown_content_type, "utf-8")
    |> Map.put(:resp_body, markdown)
  end

  def put_vary_accept(conn) do
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

  def token_estimate(markdown) do
    markdown
    |> String.length()
    |> Kernel./(4)
    |> Float.ceil()
    |> trunc()
    |> max(1)
  end

  defp maybe_put_vary_accept(conn, false), do: conn

  defp maybe_put_vary_accept(conn, true), do: put_vary_accept(conn)

  defp to_vary_values(nil), do: []

  defp to_vary_values(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end
end
