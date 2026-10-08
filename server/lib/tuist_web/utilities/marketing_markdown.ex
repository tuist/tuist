defmodule TuistWeb.Utilities.MarketingMarkdown do
  @moduledoc """
  English marketing decision guides, shared-source problem and comparison HTML,
  and unchanged policy sources.

  Keep capabilities and constraints aligned with the corresponding HTML and
  feature documentation. Individual articles retain HTML-to-Markdown negotiation;
  legal documents retain their original wording rather than a marketing summary.
  """

  alias Tuist.Docs.HTML, as: DocsHTML
  alias Tuist.Marketing.Blog
  alias Tuist.Marketing.Changelog
  alias Tuist.Marketing.Customers
  alias Tuist.Marketing.Newsletter

  @catalog_limit 20

  @guide_directory Path.expand("../../../priv/marketing/agents", __DIR__)
  @guide_patterns [
    Path.join(@guide_directory, "[a-z]*.md"),
    Path.join(@guide_directory, "solutions/[a-z]*.md"),
    Path.join(@guide_directory, "compare/[a-z]*.md")
  ]
  @policy_pattern Path.expand("../../../priv/marketing/pages/*.md", __DIR__)
  @patterns [@policy_pattern | @guide_patterns]
  @paths @patterns |> Enum.flat_map(&Path.wildcard/1) |> Enum.sort()
  @paths_digest :erlang.md5(@paths)

  for path <- @paths do
    @external_resource path
  end

  @policies Map.new(Path.wildcard(@policy_pattern), fn path ->
              [frontmatter, body] =
                path
                |> File.read!()
                |> String.replace_prefix("---\n", "")
                |> String.split("\n---\n", parts: 2)

              title = YamlElixir.read_from_string!(frontmatter)["title"]
              {"/" <> Path.basename(path, ".md"), "# #{title}\n\n" <> body}
            end)

  @guides Map.new(Enum.flat_map(@guide_patterns, &Path.wildcard/1), fn path ->
            slug = path |> Path.relative_to(@guide_directory) |> String.trim_trailing(".md")

            route =
              case slug do
                "home" -> "/"
                "compare/index" -> "/compare"
                _ -> "/" <> slug
              end

            {route, File.read!(path)}
          end)

  @pages Map.merge(@policies, @guides)

  @public_pages @guides
                |> Enum.filter(fn {path, _markdown} ->
                  path == "/compare" or String.starts_with?(path, ["/solutions/", "/compare/"])
                end)
                |> Map.new(fn {path, markdown} ->
                  [heading, description | _rest] = String.split(markdown, "\n\n")
                  {path, %{path: path, title: String.trim_leading(heading, "# "), description: description}}
                end)

  def __mix_recompile__? do
    @patterns |> Enum.flat_map(&Path.wildcard/1) |> Enum.sort() |> :erlang.md5() != @paths_digest
  end

  def __phoenix_recompile__?, do: __mix_recompile__?()

  def paths, do: @pages |> Map.keys() |> Enum.sort()
  def guide_paths, do: @guides |> Map.keys() |> Enum.sort()
  def public_pages, do: @public_pages |> Map.values() |> Enum.sort_by(& &1.path)

  def public_page(path) do
    case Map.fetch(@public_pages, path) do
      {:ok, page} ->
        [_heading, body] = String.split(Map.fetch!(@guides, path), "\n\n", parts: 2)

        body =
          Regex.replace(~r/\]\((\/[^\s)]*)\)/, body, fn _match, target ->
            "](" <> html_target(target) <> ")"
          end)

        html = body |> MDEx.to_html!(extension: [table: true]) |> DocsHTML.wrap_tables()
        Map.put(page, :body, html)

      :error ->
        nil
    end
  end

  defp html_target("/marketing-markdown"), do: "/"

  defp html_target("/marketing-markdown/" <> path = target) do
    if Map.has_key?(@pages, "/" <> path), do: "/" <> path, else: target
  end

  defp html_target("/en/docs-markdown/" <> path), do: "/en/docs/" <> path
  defp html_target(target), do: target

  def get(path) do
    case Map.fetch(@pages, path) do
      {:ok, markdown} ->
        markdown = markdown <> catalog(path)

        render(markdown)

      :error ->
        nil
    end
  end

  def source(path), do: render(Map.get(@policies, path))

  defp render(nil), do: nil

  defp render(markdown) do
    Regex.replace(~r/\]\((\/[^\s)]*)\)/, markdown, fn _match, target ->
      "](" <> Tuist.Environment.app_url(path: target) <> ")"
    end)
  end

  defp catalog(path) do
    entries =
      case path do
        "/blog" ->
          Blog.get_posts()
          |> Enum.sort_by(& &1.date, {:desc, DateTime})
          |> Enum.take(@catalog_limit)
          |> Enum.map(&{&1.title, &1.slug})

        "/changelog" ->
          Changelog.get_entries()
          |> Enum.sort_by(& &1.date, {:desc, DateTime})
          |> Enum.take(@catalog_limit)
          |> Enum.map(&{&1.title, "/changelog/#{&1.id}"})

        "/customers" ->
          "en"
          |> Customers.get_case_studies()
          |> Enum.take(@catalog_limit)
          |> Enum.map(&{&1.title, Customers.case_study_href(&1)})

        "/newsletter" ->
          Newsletter.issues()
          |> Enum.sort_by(& &1.number, :desc)
          |> Enum.take(@catalog_limit)
          |> Enum.map(&{&1.title, "/newsletter/issues/#{&1.number}"})

        _ ->
          []
      end

    if entries == [] do
      ""
    else
      links = Enum.map_join(entries, "\n", fn {title, href} -> "- [#{escape_title(title)}](#{href})" end)

      "\n## Current entries\n\n" <>
        "Up to #{@catalog_limit} recent entries. Request individual Tuist article URLs with `Accept: text/markdown` for their full content. See the [sitemap](/sitemap.xml) for further discovery. External stories use the publisher's representation.\n\n" <>
        links <> "\n"
    end
  end

  defp escape_title(title) do
    title
    |> String.replace(~r/[\r\n]+/, " ")
    |> String.replace(~r/[\\\[\]]/, fn character -> "\\" <> character end)
  end

  def alternate_path(path) do
    path = path |> URI.parse() |> Map.fetch!(:path)

    if Map.has_key?(@pages, path) do
      "/marketing-markdown" <> if(path == "/", do: "", else: path)
    end
  end
end
