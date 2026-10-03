defmodule Atlas.MCP.Tools.BrowseUrl do
  @moduledoc """
  Open a URL in a real headless browser and return its rendered text content.

  Use this when a page needs JavaScript to produce its content: SPAs,
  client-side dashboards, sites that gate content behind framework hydration,
  or anything where `search_web` snippets are too thin. Prefer
  `fetch_url_content` for plain HTML, markdown, or JSON since it's faster
  and cheaper.

  Returns the post-JS title, the final URL after redirects, and the visible
  text content (truncated to a reasonable size).
  """

  use Atlas.MCP.Tool,
    name: "browse_url",
    schema: %{
      "type" => "object",
      "required" => ["url"],
      "properties" => %{
        "url" => %{
          "type" => "string",
          "minLength" => 1,
          "description" => "Public http or https URL to open in a headless browser."
        }
      }
    },
    output_schema: %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["title", "url", "content", "truncated"],
      "properties" => %{
        "title" => %{"type" => ["string", "null"]},
        "url" => %{"type" => "string"},
        "content" => %{"type" => "string"},
        "truncated" => %{"type" => "boolean"}
      }
    }

  alias Atlas.Browser
  alias Atlas.URL, as: AtlasURL

  @impl EMCP.Tool
  def description, do: @moduledoc

  def execute(_conn, %{"url" => url}) when is_binary(url) do
    with {:ok, uri} <- AtlasURL.validate_public(url),
         {:ok, rendered} <- render(uri) do
      {:ok, rendered}
    else
      {:error, :browser_pool_not_started} ->
        {:error, "The headless browser pool is not running in this environment."}

      {:error, reason} ->
        {:error, format_error(reason)}
    end
  end

  def execute(_conn, _args), do: {:error, "url is required."}

  defp render(uri), do: Browser.render(URI.to_string(uri))

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
