defmodule Tuist.Docs.OgImage do
  @moduledoc """
  Phoenix component that renders documentation OG image cards as HTML.
  The rendered HTML is passed to Carta for screenshot capture via BrowseChrome.
  """
  use Phoenix.Component

  alias Phoenix.HTML.Safe
  alias Tuist.Docs
  alias Tuist.Docs.Sidebar
  alias Tuist.OpenGraphImageRenderer
  alias Tuist.OpenGraphImages

  @max_title_length 60
  @max_description_length 120

  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :category, :string, default: "Docs"
  attr :font_data_uri, :string, required: true
  attr :georgian_font_data_uri, :string, required: true
  attr :logo_data_uri, :string, required: true

  def card(assigns) do
    ~H"""
    <html>
      <head>
        <meta charset="utf-8" />
        <style>
          @font-face {
            font-family: 'Inter Variable';
            font-style: normal;
            font-weight: 100 900;
            src: url(<%= @font_data_uri %>) format('woff2');
          }
          @font-face {
            font-family: 'Noto Sans Georgian';
            font-style: normal;
            font-weight: 100 900;
            src: url(<%= @georgian_font_data_uri %>) format('woff2');
            unicode-range: U+0589, U+10A0-10FF, U+1C90-1CBA, U+1CBD-1CBF, U+205A, U+2D00-2D2F, U+2E31;
          }
          /*
           * Colors are hardcoded as hex instead of using Noora CSS variables because
           * headless Chrome doesn't reliably resolve oklch() values in gradient and
           * background-clip contexts. The hex equivalents match the Figma design
           * (node 352-4324) and correspond to these Noora tokens:
           *   #f4f5fe / #efe8ff  → --noora-purple-50 / --noora-purple-100 (background)
           *   #171a1c            → --noora-neutral-light-1200 (title, category)
           *   #4e575f            → --noora-neutral-light-1000 (description)
           *   #000 / #6a7581    → logo gradient (from Figma, not a direct token)
           *   #c0c8cf            → --noora-neutral-light-300 (divider)
           */
          * { margin: 0; padding: 0; box-sizing: border-box; }
          html, body {
            width: 1920px;
            height: 1080px;
            overflow: hidden;
            font-family: 'Inter Variable', 'Noto Sans Georgian', sans-serif;
            color-scheme: light;
            background: linear-gradient(180deg, #f4f5fe 0%, #efe8ff 100%);
          }
          .content {
            position: absolute;
            left: calc(50% - 191.5px);
            top: 50%;
            transform: translate(-50%, -50%);
            width: 1383px;
            display: flex;
            flex-direction: column;
            gap: 48px;
          }
          .title {
            font-size: 128px;
            font-weight: 500;
            letter-spacing: -6.4px;
            color: #171a1c;
            line-height: normal;
            word-wrap: break-word;
            overflow-wrap: break-word;
          }
          .description {
            font-size: 64px;
            font-weight: 500;
            letter-spacing: -3.2px;
            color: #4e575f;
            line-height: normal;
            word-wrap: break-word;
            overflow-wrap: break-word;
          }
          .logo-img {
            position: absolute;
            left: 67px;
            bottom: 67px;
            width: 80px;
            height: 80px;
          }
          .logo-tuist {
            position: absolute;
            left: 161px;
            bottom: 67px;
            font-size: 59px;
            font-weight: 500;
            letter-spacing: -2.9px;
            line-height: 80px;
            background: linear-gradient(92deg, #000 6%, #6a7581 109%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
          }
          .logo-divider {
            position: absolute;
            left: 290px;
            bottom: 67px;
            width: 3px;
            height: 80px;
            background-color: #c0c8cf;
          }
          .logo-docs {
            position: absolute;
            left: 305px;
            bottom: 67px;
            font-size: 59px;
            font-weight: 500;
            letter-spacing: -2.9px;
            line-height: 80px;
            background: linear-gradient(92deg, #000 6%, #6a7581 109%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
          }
          .category {
            position: absolute;
            right: 67px;
            bottom: 67px;
            font-size: 59px;
            font-weight: 500;
            letter-spacing: -2.9px;
            color: #171a1c;
            line-height: 80px;
          }
        </style>
      </head>
      <body>
        <div class="content">
          <div class="title">{truncate(@title, @max_title_length)}</div>
          <div :if={@description} class="description">
            {truncate(@description, @max_description_length)}
          </div>
        </div>
        <img class="logo-img" src={@logo_data_uri} />
        <div class="logo-tuist">Tuist</div>
        <div class="logo-divider"></div>
        <div class="logo-docs">Docs</div>
        <div class="category">{@category}</div>
      </body>
    </html>
    """
  end

  def render_html(opts) do
    title = Keyword.fetch!(opts, :title)
    description = Keyword.get(opts, :description)
    category = Keyword.get(opts, :category, "Docs")
    fonts_dir = Keyword.fetch!(opts, :fonts_dir)
    logo_path = Keyword.fetch!(opts, :logo_path)

    font_base64 = fonts_dir |> Path.join("InterVariable.woff2") |> File.read!() |> Base.encode64()
    georgian_font_base64 = fonts_dir |> Path.join("NotoSansGeorgian-georgian.woff2") |> File.read!() |> Base.encode64()
    logo_base64 = logo_path |> File.read!() |> Base.encode64()

    assigns = %{
      title: title,
      description: description,
      category: category,
      font_data_uri: "data:font/woff2;base64,#{font_base64}",
      georgian_font_data_uri: "data:font/woff2;base64,#{georgian_font_base64}",
      logo_data_uri: "data:image/webp;base64,#{logo_base64}",
      max_title_length: @max_title_length,
      max_description_length: @max_description_length
    }

    "<!DOCTYPE html>" <>
      (assigns |> card() |> Safe.to_iodata() |> IO.iodata_to_binary())
  end

  def slug_to_filename(slug) do
    [locale | rest] = String.split(slug, "/", trim: true)
    page_path = rest |> Enum.join("-") |> then(&"#{&1}.jpg")
    Path.join(locale, page_path)
  end

  def image_path(page) do
    # Derive both the URL and the content key from the page's canonical slug so
    # generation matches what resolve/1 reconstructs at serve time. Keying off
    # the raw requested path instead diverges whenever Docs.get_page/1
    # normalizes the URL (trailing slash, "/index" suffix), producing a key the
    # controller cannot reproduce and a 404 for the social card.
    path = "/docs/images/og/generated/#{slug_to_filename(page.slug)}"
    spec = spec(page.slug, page)
    OpenGraphImages.versioned_path(path, spec.key)
  end

  def resolve(path) do
    prefix = "/docs/images/og/generated/"

    with true <- String.starts_with?(path, prefix),
         relative_path = String.replace_prefix(path, prefix, ""),
         true <- String.ends_with?(relative_path, ".jpg"),
         {slug, page} when not is_nil(page) <- page_for_filename(relative_path) do
      {:ok, spec(slug, page)}
    else
      _ -> :error
    end
  end

  defp page_for_filename(filename) do
    case Enum.find(Docs.pages(), &(slug_to_filename(&1.slug) == filename)) do
      nil -> localized_fallback_page(filename)
      page -> {page.slug, page}
    end
  end

  defp localized_fallback_page(filename) do
    case String.split(filename, "/", parts: 2) do
      [locale, page_filename] when locale != "en" ->
        english_filename = Path.join("en", page_filename)

        case Enum.find(Docs.pages(), &(slug_to_filename(&1.slug) == english_filename)) do
          nil -> {nil, nil}
          page -> {String.replace_prefix(page.slug, "/en/", "/#{locale}/"), page}
        end

      _ ->
        {nil, nil}
    end
  end

  defp spec(slug, page) do
    priv_dir = Application.app_dir(:tuist, "priv")
    fonts_dir = Path.join(priv_dir, "static/fonts")
    logo_path = Path.join(priv_dir, "docs/images/logo.webp")
    category = category(slug)

    key_parts = [
      "docs-page:v2",
      slug,
      page.title || "",
      page.description || "",
      category,
      asset_hash()
    ]

    OpenGraphImages.spec(key_parts, fn ->
      html =
        render_html(
          title: page.title,
          description: page.description,
          category: category,
          fonts_dir: fonts_dir,
          logo_path: logo_path
        )

      OpenGraphImageRenderer.render(html, page.title || category)
    end)
  end

  defp category(slug) do
    en_slug = String.replace(slug, ~r{^/[^/]+/}, "/en/")

    Sidebar.tree()
    |> Enum.flat_map(fn group -> collect_slugs_with_category(group.label || "Docs", group.items) end)
    |> Map.new()
    |> Map.get(en_slug, "Docs")
  end

  defp collect_slugs_with_category(category, items) do
    Enum.flat_map(items, fn item ->
      own = if item.slug, do: [{item.slug, category}], else: []
      own ++ collect_slugs_with_category(category, item.items)
    end)
  end

  defp asset_hash do
    priv_dir = Application.app_dir(:tuist, "priv")

    OpenGraphImages.cached_key(:docs_open_graph_assets, [
      {:module, __MODULE__},
      {:dir, Path.join(priv_dir, "static/fonts")},
      {:file, Path.join(priv_dir, "docs/images/logo.webp")}
    ])
  end

  defp truncate(nil, _max), do: ""

  defp truncate(text, max) do
    if String.length(text) > max do
      text |> String.slice(0, max) |> String.trim_trailing() |> Kernel.<>("...")
    else
      text
    end
  end
end
