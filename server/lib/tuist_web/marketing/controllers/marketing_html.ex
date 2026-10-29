defmodule TuistWeb.Marketing.MarketingHTML do
  use TuistWeb, :html
  use Noora

  import TuistWeb.Marketing.MarketingFrameworkLogos
  import TuistWeb.Marketing.MarketingIllustrations
  import TuistWeb.Marketing.MarketingOrgLogos

  embed_templates("marketing_html/*")
  embed_templates("marketing_html/blog/*")

  # Delegate to Localization module
  defdelegate localized_href(href), to: TuistWeb.Marketing.Localization

  def static_asset_path(nil), do: nil

  def static_asset_path(source) do
    uri = URI.parse(source)
    app_uri = URI.parse(Tuist.Environment.app_url())

    if static_asset_uri?(uri, app_uri) do
      uri.path
      |> TuistWeb.Endpoint.static_path()
      |> append_query(uri.query)
      |> append_fragment(uri.fragment)
    else
      source
    end
  end

  def content_html(nil), do: nil

  def content_html(html) do
    # Floki drops whitespace-only text nodes when it re-serializes, which
    # collapses the significant spacing inside highlighted <pre> code blocks
    # (indentation and the spaces the syntax highlighter puts between tokens).
    # Protect those blocks, run the image optimization on the rest, then
    # restore them verbatim.
    {protected, pre_blocks} = protect_pre_blocks(html)

    processed =
      case Floki.parse_fragment(protected) do
        {:ok, document} ->
          document
          |> Floki.traverse_and_update(fn
            {"img", attrs, children} ->
              {"img", optimize_image_attrs(attrs), children}

            node ->
              node
          end)
          |> Floki.raw_html()

        {:error, _reason} ->
          protected
      end

    restore_pre_blocks(processed, pre_blocks)
  end

  defp protect_pre_blocks(html) do
    ~r/<pre\b.*?<\/pre>/s
    |> Regex.scan(html)
    |> Enum.map(fn [block] -> block end)
    |> Enum.with_index()
    |> Enum.reduce({html, []}, fn {block, index}, {acc, blocks} ->
      placeholder = "ONCE_PRE_PLACEHOLDER_#{index}_ENDONCE"
      {String.replace(acc, block, placeholder, global: false), [{placeholder, block} | blocks]}
    end)
  end

  defp restore_pre_blocks(html, blocks) do
    Enum.reduce(blocks, html, fn {placeholder, block}, acc ->
      String.replace(acc, placeholder, block)
    end)
  end

  defp static_asset_uri?(%URI{path: path} = uri, app_uri) when is_binary(path) do
    String.starts_with?(path, "/") and
      (is_nil(uri.host) or uri.host == app_uri.host) and
      (is_nil(uri.scheme) or uri.scheme == app_uri.scheme)
  end

  defp static_asset_uri?(_uri, _app_uri), do: false

  defp optimize_image_attrs(attrs) do
    attrs
    |> update_attr("src", &static_asset_path/1)
    |> put_new_attr("loading", "lazy")
    |> put_new_attr("decoding", "async")
  end

  defp update_attr(attrs, key, update) do
    Enum.map(attrs, fn
      {^key, value} -> {key, update.(value)}
      attr -> attr
    end)
  end

  defp put_new_attr(attrs, key, value) do
    if Enum.any?(attrs, fn {name, _value} -> name == key end) do
      attrs
    else
      attrs ++ [{key, value}]
    end
  end

  defp append_query(path, nil), do: path

  defp append_query(path, query) do
    separator = if String.contains?(path, "?"), do: "&", else: "?"
    path <> separator <> query
  end

  defp append_fragment(path, nil), do: path
  defp append_fragment(path, fragment), do: path <> "#" <> fragment

  def language(assigns) do
    ~H"""
    <svg width="20" height="20" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path
        d="M10 18.3333C14.6024 18.3333 18.3333 14.6024 18.3333 10C18.3333 5.39763 14.6024 1.66667 10 1.66667C5.39763 1.66667 1.66667 5.39763 1.66667 10C1.66667 14.6024 5.39763 18.3333 10 18.3333Z"
        stroke="currentColor"
        stroke-width="1.5"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
      <path
        d="M1.66667 10H18.3333"
        stroke="currentColor"
        stroke-width="1.5"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
      <path
        d="M10 1.66667C12.0844 3.94863 13.2698 6.91003 13.3333 10C13.2698 13.09 12.0844 16.0514 10 18.3333C7.91561 16.0514 6.73021 13.09 6.66667 10C6.73021 6.91003 7.91561 3.94863 10 1.66667Z"
        stroke="currentColor"
        stroke-width="1.5"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end
end
