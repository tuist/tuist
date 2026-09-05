defmodule Tuist.OpenGraphImageTemplates do
  @moduledoc """
  Builds render specifications for the supported Open Graph image templates.

  Page ownership stays in controllers and LiveViews: callers choose a template
  and pass every variable that affects its output. This module only validates
  those variables, resolves trusted template assets, and renders the image.
  """

  alias Tuist.Docs.OgImage, as: DocsImage
  alias Tuist.Marketing.Changelog.OgImage, as: ChangelogImage
  alias Tuist.Marketing.OgImages, as: MarketingImages
  alias Tuist.Marketing.OpenGraph
  alias Tuist.OpenGraph.ProjectImage
  alias Tuist.OpenGraphImageRenderer
  alias Tuist.OpenGraphImages
  alias Tuist.Projects
  alias Tuist.Projects.Project

  @max_title_length 240
  @max_description_length 500

  def spec(%{"template" => "marketing", "title" => title} = params) do
    with true <- allowed_keys?(params, ["template", "title"], ["icon"]),
         true <- valid_text?(title, @max_title_length),
         {:ok, icon_path} <- marketing_icon_path(Map.get(params, "icon")) do
      marketing_spec(params, title, icon_path)
    else
      _ -> :error
    end
  end

  def spec(%{"template" => template, "title" => title} = params)
      when template in [
             "marketing_home",
             "marketing_blog",
             "marketing_changelog",
             "marketing_newsletter",
             "marketing_api_docs"
           ] do
    if allowed_keys?(params, ["template", "title"], []) and valid_text?(title, @max_title_length) do
      marketing_layout_spec(params, template, title)
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
      logo_path = Path.join(priv_dir, "docs/images/logo.webp")

      build_spec(params, docs_asset_hash(), fn ->
        html =
          DocsImage.render_html(
            title: title,
            description: description,
            category: category,
            fonts_dir: fonts_dir,
            logo_path: logo_path
          )

        OpenGraphImageRenderer.render(html, title)
      end)
    else
      :error
    end
  end

  def spec(%{"template" => "changelog_entry", "title" => title} = params) do
    description = Map.get(params, "description")
    date = Map.get(params, "date")

    with true <-
           allowed_keys?(
             params,
             ["template", "title"],
             ["description", "date", "pull_request"]
           ),
         true <- valid_text?(title, @max_title_length),
         true <- valid_optional_text?(description, @max_description_length),
         true <- valid_optional_text?(date, @max_title_length),
         {:ok, pull_request} <- optional_positive_integer(Map.get(params, "pull_request")) do
      priv_dir = Application.app_dir(:tuist, "priv")
      fonts_dir = Path.join(priv_dir, "static/fonts")
      logo_path = Path.join(priv_dir, "docs/images/logo.webp")

      build_spec(params, changelog_asset_hash(), fn ->
        html =
          ChangelogImage.render_html(
            title: title,
            description: description,
            date: date,
            pull_request: pull_request,
            fonts_dir: fonts_dir,
            logo_path: logo_path
          )

        OpenGraphImageRenderer.render(html, title)
      end)
    else
      _ -> :error
    end
  end

  def spec(%{"template" => "project", "title" => title, "project" => project} = params) do
    optional_keys = [
      "subtitle",
      "badge",
      "metric_one_label",
      "metric_one_value",
      "metric_two_label",
      "metric_two_value",
      "chart",
      "chart_label",
      "chart_kind",
      "chart_categories",
      "locale"
    ]

    with true <- allowed_keys?(params, ["template", "title", "project"], optional_keys),
         true <- valid_text?(title, 160),
         true <- valid_text?(project, 510),
         true <- valid_optional_text?(Map.get(params, "subtitle"), 200),
         true <- valid_optional_text?(Map.get(params, "badge"), 60),
         true <- valid_optional_text?(Map.get(params, "metric_one_label"), 80),
         true <- valid_optional_text?(Map.get(params, "metric_one_value"), 100),
         true <- valid_optional_text?(Map.get(params, "metric_two_label"), 80),
         true <- valid_optional_text?(Map.get(params, "metric_two_value"), 100),
         true <- valid_optional_text?(Map.get(params, "chart_label"), 100),
         true <- valid_optional_text?(Map.get(params, "locale"), 20),
         {:ok, chart} <- chart_values(Map.get(params, "chart")),
         {:ok, chart_kind} <- chart_kind(Map.get(params, "chart_kind"), chart),
         {:ok, chart_categories} <- chart_categories(Map.get(params, "chart_categories"), chart, chart_kind),
         true <- valid_chart_label?(Map.get(params, "chart_label"), chart),
         {:ok, resolved_project} <- public_project(project) do
      project_spec(params, title, resolved_project, chart, chart_kind, chart_categories)
    else
      _ -> :error
    end
  end

  def spec(_params), do: :error

  defp marketing_spec(params, title, icon_path) do
    priv_dir = Application.app_dir(:tuist, "priv")
    fonts_dir = Path.join(priv_dir, "static/fonts")
    logo_path = Path.join(priv_dir, "docs/images/logo.webp")
    background_path = Path.join(priv_dir, "static/marketing/images/background.webp")

    asset_hash = OpenGraphImages.key([marketing_asset_hash(), icon_path && {:file, icon_path}])

    build_spec(params, asset_hash, fn ->
      opts = [title: title, fonts_dir: fonts_dir, logo_path: logo_path, bg_path: background_path]
      opts = if icon_path, do: Keyword.put(opts, :icon_path, icon_path), else: opts
      html = MarketingImages.render_html(opts)
      OpenGraphImageRenderer.render(html, title)
    end)
  end

  defp marketing_layout_spec(params, template, title) do
    priv_dir = Application.app_dir(:tuist, "priv")
    fonts_dir = Path.join(priv_dir, "static/fonts")
    logo_path = Path.join(priv_dir, "docs/images/logo.webp")
    background_path = Path.join(priv_dir, "static/marketing/images/background.webp")

    build_spec(params, marketing_asset_hash(), fn ->
      common_opts = [
        title: title,
        fonts_dir: fonts_dir,
        logo_path: logo_path,
        bg_path: background_path
      ]

      html =
        case template do
          "marketing_home" ->
            phone_path = Path.join(priv_dir, "static/marketing/images/og/phone.png")
            MarketingImages.render_home_html(Keyword.put(common_opts, :phone_path, phone_path))

          "marketing_blog" ->
            MarketingImages.render_blog_html(common_opts)

          "marketing_changelog" ->
            timeline_path = Path.join(priv_dir, "static/marketing/images/og/changelog-timeline.svg")
            MarketingImages.render_changelog_list_html(Keyword.put(common_opts, :timeline_path, timeline_path))

          "marketing_newsletter" ->
            icon_path = Path.join(priv_dir, "static/marketing/images/newsletter/envelope.webp")
            MarketingImages.render_newsletter_html(Keyword.put(common_opts, :icon_path, icon_path))

          "marketing_api_docs" ->
            MarketingImages.render_api_docs_html(common_opts)
        end

      OpenGraphImageRenderer.render(html, title)
    end)
  end

  defp project_spec(params, title, %Project{} = project, chart, chart_kind, chart_categories) do
    priv_dir = Application.app_dir(:tuist, "priv")
    fonts_dir = Path.join(priv_dir, "static/fonts")
    tuist_logo_path = Path.join(priv_dir, "docs/images/logo.webp")

    asset_hash = OpenGraphImages.key([project_asset_hash(), project.logo_storage_key || ""])

    build_spec(params, asset_hash, fn ->
      with {:ok, {logo_binary, logo_content_type}} <- project_logo(project) do
        html =
          ProjectImage.render_html(
            title: title,
            project: Map.fetch!(params, "project"),
            subtitle: Map.get(params, "subtitle"),
            badge: Map.get(params, "badge"),
            metric_one_label: Map.get(params, "metric_one_label"),
            metric_one_value: Map.get(params, "metric_one_value"),
            metric_two_label: Map.get(params, "metric_two_label"),
            metric_two_value: Map.get(params, "metric_two_value"),
            chart: chart,
            chart_label: Map.get(params, "chart_label"),
            chart_kind: chart_kind,
            chart_categories: chart_categories,
            logo_binary: logo_binary,
            logo_content_type: logo_content_type,
            fonts_dir: fonts_dir,
            tuist_logo_path: tuist_logo_path
          )

        OpenGraphImageRenderer.render(html, title)
      end
    end)
  end

  defp build_spec(params, asset_hash, render) do
    key_parts =
      ["open-graph-image:v3"] ++
        Enum.flat_map(Enum.sort(params), fn {key, value} -> [key, value] end) ++
        [asset_hash]

    {:ok, OpenGraphImages.spec(key_parts, params, render)}
  end

  defp marketing_icon_path(nil), do: {:ok, nil}

  defp marketing_icon_path(relative_path) do
    priv_dir = Application.app_dir(:tuist, "priv")
    icon_path = Path.expand(relative_path, priv_dir)

    if String.starts_with?(icon_path, priv_dir <> "/") and File.regular?(icon_path) do
      {:ok, icon_path}
    else
      :error
    end
  end

  defp marketing_asset_hash do
    priv_dir = Application.app_dir(:tuist, "priv")

    OpenGraphImages.cached_key(:marketing_open_graph_template_assets, [
      {:module, MarketingImages},
      {:dir, Path.join(priv_dir, "static/fonts")},
      {:file, Path.join(priv_dir, "docs/images/logo.webp")},
      {:file, Path.join(priv_dir, "static/marketing/images/background.webp")},
      {:file, Path.join(priv_dir, "static/marketing/images/newsletter/envelope.webp")},
      {:file, Path.join(priv_dir, "static/marketing/images/og/phone.png")},
      {:file, Path.join(priv_dir, "static/marketing/images/og/changelog-timeline.svg")}
    ])
  end

  defp docs_asset_hash do
    priv_dir = Application.app_dir(:tuist, "priv")

    OpenGraphImages.cached_key(:docs_open_graph_template_assets, [
      {:module, DocsImage},
      {:dir, Path.join(priv_dir, "static/fonts")},
      {:file, Path.join(priv_dir, "docs/images/logo.webp")}
    ])
  end

  defp changelog_asset_hash do
    priv_dir = Application.app_dir(:tuist, "priv")

    OpenGraphImages.cached_key(:changelog_open_graph_template_assets, [
      {:module, ChangelogImage},
      {:dir, Path.join(priv_dir, "static/fonts")},
      {:file, Path.join(priv_dir, "docs/images/logo.webp")}
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

  defp project_asset_hash do
    priv_dir = Application.app_dir(:tuist, "priv")

    OpenGraphImages.cached_key(:project_open_graph_template_assets, [
      {:module, ProjectImage},
      {:dir, Path.join(priv_dir, "static/fonts")},
      {:file, Path.join(priv_dir, "docs/images/logo.webp")}
    ])
  end

  defp project_logo(%Project{logo_storage_key: nil}), do: {:ok, {nil, nil}}

  defp project_logo(%Project{} = project) do
    case Projects.read_project_logo(project) do
      {:ok, binary} -> {:ok, {binary, Projects.project_logo_content_type(project)}}
      {:error, reason} -> {:error, {:project_logo_unavailable, reason}}
    end
  end

  defp public_project(slug) do
    case Projects.get_project_by_slug(slug) do
      {:ok, %Project{visibility: :public} = project} -> {:ok, project}
      _ -> :error
    end
  end

  defp chart_values(nil), do: {:ok, []}

  defp chart_values(value) when is_binary(value) do
    values = String.split(value, ",", trim: true)

    if length(values) in 2..16 do
      values
      |> Enum.reduce_while({:ok, []}, fn value, {:ok, parsed} ->
        case Integer.parse(value) do
          {integer, ""} when integer >= 0 and integer <= 9_007_199_254_740_991 ->
            {:cont, {:ok, [integer | parsed]}}

          _ ->
            {:halt, :error}
        end
      end)
      |> case do
        {:ok, parsed} -> {:ok, Enum.reverse(parsed)}
        :error -> :error
      end
    else
      :error
    end
  end

  defp chart_values(_value), do: :error

  defp chart_kind(nil, []), do: {:ok, "line"}
  defp chart_kind(nil, _chart), do: {:ok, "line"}
  defp chart_kind(kind, _chart) when kind in ["line", "bars"], do: {:ok, kind}
  defp chart_kind(_kind, _chart), do: :error

  defp chart_categories(nil, _chart, "line"), do: {:ok, []}

  defp chart_categories(value, chart, "bars") when is_binary(value) do
    categories = String.split(value, "|", trim: true)

    if length(categories) == length(chart) and
         Enum.all?(categories, &valid_text?(&1, 30)) do
      {:ok, categories}
    else
      :error
    end
  end

  defp chart_categories(_value, _chart, _kind), do: :error

  defp valid_chart_label?(nil, []), do: true
  defp valid_chart_label?(label, chart) when chart != [], do: valid_text?(label, 100)
  defp valid_chart_label?(_label, _chart), do: false

  defp allowed_keys?(params, required, optional) do
    keys = Map.keys(params)
    Enum.all?(required, &(&1 in keys)) and Enum.all?(keys, &(&1 in required or &1 in optional))
  end

  defp valid_text?(value, max_length) do
    is_binary(value) and value != "" and String.length(value) <= max_length
  end

  defp valid_optional_text?(nil, _max_length), do: true
  defp valid_optional_text?(value, max_length), do: valid_text?(value, max_length)

  defp optional_positive_integer(nil), do: {:ok, nil}

  defp optional_positive_integer(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> {:ok, integer}
      _ -> :error
    end
  end
end
