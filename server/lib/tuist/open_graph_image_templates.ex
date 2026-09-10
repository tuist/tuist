defmodule Tuist.OpenGraphImageTemplates do
  @moduledoc """
  Builds render specifications for the supported Open Graph image templates.

  Page ownership stays in controllers and LiveViews: callers choose a template
  and pass every variable that affects its output. This module only validates
  those variables, resolves trusted template assets, and renders the image.
  """

  alias Tuist.Docs.OgImage, as: DocsImage
  alias Tuist.Marketing.Blog.CoverArtwork, as: BlogCoverArtwork
  alias Tuist.Marketing.Customers.CoverArtwork
  alias Tuist.Marketing.OgImages, as: MarketingImages
  alias Tuist.Marketing.OpenGraph
  alias Tuist.OpenGraphImageRenderer
  alias Tuist.OpenGraphImages

  @max_title_length 500
  @max_description_length 1_000

  def spec(%{"template" => "marketing", "title" => title} = params) do
    if allowed_keys?(params, ["template", "title"], []) and valid_text?(title, @max_title_length) do
      build_spec(params, marketing_asset_hash(), fn ->
        OpenGraph.generate_title_card_binary(title)
      end)
    else
      :error
    end
  end

  def spec(%{"template" => "marketing_text", "title" => title} = params) do
    if allowed_keys?(params, ["template", "title"], []) and valid_text?(title, @max_title_length) do
      build_spec(params, marketing_text_asset_hash(), fn ->
        OpenGraph.generate_og_image_binary(title)
      end)
    else
      :error
    end
  end

  def spec(%{"template" => "docs", "title" => title} = params) do
    description = Map.get(params, "description")
    category = Map.get(params, "category", "Docs")

    if allowed_keys?(params, ["template", "title"], ["description", "category"]) and
         valid_text?(title, @max_title_length) and
         valid_optional_text?(description, @max_description_length) and
         valid_text?(category, @max_title_length) do
      priv_dir = Application.app_dir(:tuist, "priv")
      fonts_dir = Path.join(priv_dir, "static/fonts")

      build_spec(params, docs_asset_hash(), fn ->
        html =
          DocsImage.render_html(
            title: title,
            description: description,
            category: category,
            fonts_dir: fonts_dir
          )

        OpenGraphImageRenderer.render(html, title)
      end)
    else
      :error
    end
  end

  def spec(%{"template" => "marketing_case_study", "slug" => slug} = params) do
    if allowed_keys?(params, ["template", "slug"], []) and CoverArtwork.available?(slug) do
      # The SVG is the render's whole input, so hashing it into the key
      # busts the cache whenever the logo file or the artwork generator
      # changes; the module digest covers the HTML wrapper around it.
      svg = CoverArtwork.svg(slug, :og)
      asset_hash = OpenGraphImages.key([case_study_asset_hash(), svg])

      build_spec(params, asset_hash, fn ->
        html = MarketingImages.render_case_study_html(svg: svg)
        OpenGraphImageRenderer.render(html, slug)
      end)
    else
      :error
    end
  end

  def spec(%{"template" => "marketing_blog_cover", "slug" => slug} = params) do
    if allowed_keys?(params, ["template", "slug"], []) and BlogCoverArtwork.available?(slug) do
      # As for case studies: the SVG is the render's whole input, so it is
      # hashed into the key and the dark variant fills the same 16:9 wrapper.
      svg = BlogCoverArtwork.svg(slug, :og)
      asset_hash = OpenGraphImages.key([blog_cover_asset_hash(), svg])

      build_spec(params, asset_hash, fn ->
        html = MarketingImages.render_case_study_html(svg: svg)
        OpenGraphImageRenderer.render(html, slug)
      end)
    else
      :error
    end
  end

  def spec(_params), do: :error

  defp build_spec(params, asset_hash, render) do
    key_parts =
      ["open-graph-image:v3"] ++
        Enum.flat_map(Enum.sort(params), fn {key, value} -> [key, value] end) ++
        [asset_hash]

    {:ok, OpenGraphImages.spec(key_parts, params, render)}
  end

  defp marketing_asset_hash do
    priv_dir = Application.app_dir(:tuist, "priv")

    OpenGraphImages.cached_key(:marketing_open_graph_template_assets, [
      {:module, OpenGraph},
      {:file, Path.join(priv_dir, "static/images/og_marketing_template.png")},
      {:dir, Path.join(priv_dir, "static/fonts")}
    ])
  end

  defp docs_asset_hash do
    priv_dir = Application.app_dir(:tuist, "priv")

    OpenGraphImages.cached_key(:docs_open_graph_template_assets, [
      {:module, DocsImage},
      {:dir, Path.join(priv_dir, "static/fonts")}
    ])
  end

  defp case_study_asset_hash do
    OpenGraphImages.cached_key(:marketing_case_study_open_graph_template_assets, [
      {:module, MarketingImages},
      {:module, CoverArtwork}
    ])
  end

  defp blog_cover_asset_hash do
    OpenGraphImages.cached_key(:marketing_blog_cover_open_graph_template_assets, [
      {:module, MarketingImages},
      {:module, BlogCoverArtwork}
    ])
  end

  defp marketing_text_asset_hash do
    priv_dir = Application.app_dir(:tuist, "priv")

    OpenGraphImages.cached_key(:marketing_text_open_graph_template_assets, [
      {:module, OpenGraph},
      {:file, Path.join(priv_dir, "static/images/og_template.png")},
      {:dir, Path.join(priv_dir, "static/fonts")}
    ])
  end

  defp allowed_keys?(params, required, optional) do
    keys = Map.keys(params)
    Enum.all?(required, &(&1 in keys)) and Enum.all?(keys, &(&1 in required or &1 in optional))
  end

  defp valid_text?(value, max_length) do
    is_binary(value) and value != "" and String.length(value) <= max_length
  end

  defp valid_optional_text?(nil, _max_length), do: true
  defp valid_optional_text?(value, max_length), do: valid_text?(value, max_length)
end
