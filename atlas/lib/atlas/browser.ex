defmodule Atlas.Browser do
  @moduledoc """
  Headless-browser rendering of public URLs via the BrowseChrome pool.

  This is the seam between Atlas tooling (e.g. the `browse_url` MCP tool)
  and the underlying browser implementation. Callers ask for a rendered
  view of a page and get back its post-JS title, text content, and final
  URL after redirects. The pool is configured under `:browse_chrome` and
  is only started when `CHROME_PATH` is set (see `config/runtime.exs`).
  """

  @max_content_chars 20_000
  @navigation_timeout 30_000

  @doc """
  Renders `url` in a headless browser and returns its post-JS content.

  Returns `{:error, :browser_pool_not_started}` when the BrowseChrome pool
  isn't running in this environment (typically dev/test without
  `CHROME_PATH` set).
  """
  def render(url) when is_binary(url) do
    if pool_running?() do
      BrowseChrome.checkout(default_pool!(), &render_in_browser(&1, url))
    else
      {:error, :browser_pool_not_started}
    end
  end

  defp render_in_browser(browser, url) do
    with {:ok, ws_url} <- BrowseChrome.Chrome.ws_url(browser) do
      BrowseChrome.CDP.with_session(ws_url, fn cdp ->
        case BrowseChrome.CDP.navigate(cdp, url) do
          :ok -> extract(cdp)
          {:error, reason} -> {:error, format_error(reason)}
        end
      end)
    end
  end

  defp extract(cdp) do
    expression = """
    JSON.stringify({
      title: document.title || null,
      url: window.location.href,
      content: document.documentElement && document.documentElement.innerText || ""
    })
    """

    params = %{expression: expression, returnByValue: true, timeout: @navigation_timeout}

    case BrowseChrome.CDP.command(cdp, "Runtime.evaluate", params) do
      {:ok, %{"result" => %{"value" => json}}} when is_binary(json) ->
        decode_extraction(json)

      {:ok, %{"exceptionDetails" => details}} ->
        {:error, format_error(details["text"] || "Runtime.evaluate raised")}

      {:ok, other} ->
        {:error, format_error("unexpected Runtime.evaluate response: #{inspect(other)}")}

      {:error, reason} ->
        {:error, format_error(reason)}
    end
  end

  defp decode_extraction(json) do
    case JSON.decode(json) do
      {:ok, %{"url" => final_url, "content" => content} = payload} when is_binary(final_url) ->
        {trimmed, truncated?} = truncate(content || "")

        {:ok,
         %{
           title: blank_to_nil(payload["title"]),
           url: final_url,
           content: trimmed,
           truncated: truncated?
         }}

      {:ok, other} ->
        {:error, format_error("unexpected extraction payload: #{inspect(other)}")}

      {:error, reason} ->
        {:error, format_error(reason)}
    end
  end

  defp truncate(content) when is_binary(content) do
    if String.length(content) > @max_content_chars do
      {String.slice(content, 0, @max_content_chars), true}
    else
      {content, false}
    end
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_other), do: nil

  defp pool_running? do
    case Application.get_env(:browse_chrome, :pools, []) do
      [] -> false
      _pools -> true
    end
  end

  defp default_pool! do
    Application.get_env(:browse_chrome, :default_pool) ||
      raise "BrowseChrome default pool not configured"
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
