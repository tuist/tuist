defmodule AtlasWeb.Plugs.DocsMarkdownNegotiation do
  @moduledoc false
  import Plug.Conn

  alias Plug.Conn.Utils

  def init(opts), do: opts

  def call(conn, _opts) do
    preferences =
      conn
      |> get_req_header("accept")
      |> Enum.flat_map(&String.split(&1, ","))
      |> Enum.flat_map(fn value ->
        case Utils.media_type(String.trim(value)) do
          {:ok, type, subtype, params} -> [{type <> "/" <> subtype, quality(params)}]
          _ -> []
        end
      end)

    markdown = preference(preferences, ["text/markdown"])
    html = preference(preferences, ["text/html", "text/*", "*/*"])
    requested? = markdown > 0 and markdown >= html
    conn = conn |> put_private(:docs_markdown_requested, requested?) |> put_resp_header("vary", "Accept")

    if requested?, do: put_req_header(conn, "accept", "text/html"), else: conn
  end

  defp preference(preferences, types) do
    Enum.find_value(types, 0.0, fn type ->
      case Enum.filter(preferences, fn {media_type, _quality} -> media_type == type end) do
        [] -> nil
        matches -> {:quality, matches |> Enum.map(&elem(&1, 1)) |> Enum.max()}
      end
    end)
    |> case do
      {:quality, quality} -> quality
      quality -> quality
    end
  end

  defp quality(params) do
    case Float.parse(Map.get(params, "q", "1")) do
      {value, ""} when value >= 0 and value <= 1 -> value
      _ -> 0.0
    end
  end
end
