defmodule TuistWeb.Utilities.LlmsTxt do
  @moduledoc """
  Builds the `/llms.txt` index described by https://llmstxt.org.

  The file is the entry point agents and AI crawlers look for when they want a
  curated map of a site instead of crawling it. Ours points at the Markdown twin
  of every documentation page (`/:locale/docs-markdown/*`), which is otherwise
  undiscoverable: nothing links to it and it is absent from the sitemap.

  Only English is indexed. The file lives at a single URL, so a translated
  variant would have nowhere to be served from.
  """

  alias Tuist.Docs
  alias Tuist.Docs.Paths
  alias Tuist.KeyValueStore
  alias TuistWeb.Utilities.MarketingMarkdown

  @locale "en"

  @summary "Tuist is build infrastructure for productive teams. It integrates into existing build toolchains to share a binary cache across machines and CI, run only the tests a change can affect, track flaky tests, surface build and test insights, and share app previews from a URL."

  @notes [
    "Every documentation page has a plain-Markdown twin: swap `/docs/` for `/docs-markdown/` in any documentation URL to get the Markdown source instead of the rendered HTML page.",
    "Marketing landing pages have purpose-written English decision guides at `/marketing-markdown` and `/marketing-markdown/<page>`. Policy documents retain their original wording, and `/marketing-markdown/source/<page>` exposes full original company statements. You can also request `Accept: text/markdown` on marketing and documentation pages; individual marketing articles are converted from HTML.",
    "Tuist's source is public at https://github.com/tuist/tuist. Component licenses differ; see the Openness guide before assuming the server and CLI use the same license."
  ]

  @product_pages [
    {"/", "What Tuist solves, which products to adopt, and how to get started."},
    {"/cache", "Reuse compatible build artifacts across machines and CI with Xcode, Gradle, and Bazel."},
    {"/compute", "Managed macOS and Linux CI runners with a colocated cache; currently invite-only."},
    {"/tests", "Test insights, flaky-test tracking, sharding, and selective testing, with toolchain-specific support."},
    {"/previews", "Share iOS and Android app builds through a URL for feedback before store distribution."}
  ]

  @company_pages [
    {"/pricing", "Plans, usage-based pricing, and free tier limits."},
    {"/download", "Choose the CLI, macOS app, or iOS app for the intended workflow."},
    {"/brand", "Official brand assets and trademark usage guidelines."},
    {"/about", "What Tuist is, who builds it, and why."},
    {"/customers", "How teams use Tuist at scale."},
    {"/community", "Community channels and contributors."},
    {"/security", "Security practices and vulnerability reporting."},
    {"/openness", "How Tuist works in the open."},
    {"/longevity", "The commitments behind depending on Tuist long term."}
  ]

  @optional_pages [
    {"/blog", "Long-form engineering writing on build systems, caching, and developer infrastructure."},
    {"/changelog", "Every user-facing change, newest first."},
    {"/newsletter", "Tuist Digest, product updates and perspectives from the team."},
    {"/globe", "How to interpret the aggregate cache activity display and its limitations."},
    {"/sitemap.xml", "Every indexable URL on the site."}
  ]

  @policy_pages [
    {"/terms", "Terms of service, in their original wording."},
    {"/privacy", "Privacy policy."},
    {"/cookies", "Cookie policy."},
    {"/data-processing-addendum", "Data processing terms."},
    {"/data-act-addendum", "Data Act terms."},
    {"/service-level-addendum", "Service-level terms."},
    {"/imprint", "Company identification and legal notices."},
    {"/trademark-guidelines", "Trademark usage rules."}
  ]

  @section_labels %{
    "overview" => "Documentation",
    "guides" => "Documentation: Guides",
    "tutorials" => "Documentation: Tutorials",
    "cli" => "Documentation: CLI reference",
    "references" => "Documentation: References",
    "contributors" => "Documentation: Contributing",
    "server" => "Documentation: Server"
  }

  # Sections are emitted in this order; anything unrecognized follows, sorted.
  @section_order ["overview", "guides", "tutorials", "cli", "references", "contributors", "server"]

  @cache_ttl to_timeout(hour: 1)

  @doc """
  Renders the index, memoized for an hour.

  Building it walks every documentation page, and the command-line pages are
  fetched from the latest GitHub release on a cold cache. This endpoint exists
  for crawlers, so it should not tie a request to that fetch more than once an
  hour.
  """
  def render do
    KeyValueStore.get_or_update([__MODULE__, "llms_txt"], [ttl: @cache_ttl], &build/0)
  end

  defp build do
    [
      ["# Tuist", "", "> #{@summary}", ""],
      Enum.flat_map(@notes, &["- #{&1}"]),
      [""],
      documentation_sections(),
      link_section("Product", @product_pages),
      link_section("Company", @company_pages),
      link_section("Policies", @policy_pages),
      link_section("Optional", @optional_pages)
    ]
    |> List.flatten()
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  # The llms.txt format delimits each list of links with an H2. Nesting the
  # documentation groups under a single "## Documentation" H3-style heading would
  # leave that section with no list directly beneath it, so each group gets its
  # own H2 instead.
  defp documentation_sections do
    sections =
      Docs.pages()
      |> Enum.filter(&english_page?/1)
      |> Enum.group_by(&section_key/1)

    Enum.flat_map(ordered_sections(sections), fn {key, pages} ->
      ["## #{section_label(key)}", ""] ++
        Enum.map(Enum.sort_by(pages, & &1.slug), &page_line/1) ++ [""]
    end)
  end

  defp ordered_sections(sections) do
    known = Enum.filter(@section_order, &Map.has_key?(sections, &1))
    rest = sections |> Map.keys() |> Kernel.--(@section_order) |> Enum.sort()

    Enum.map(known ++ rest, &{&1, Map.fetch!(sections, &1)})
  end

  defp english_page?(%{slug: slug}) do
    match?([@locale | _], String.split(slug, "/", trim: true))
  end

  defp section_key(%{slug: slug}) do
    case String.split(slug, "/", trim: true) do
      [@locale, section | _] -> section
      _ -> "overview"
    end
  end

  defp section_label(key) do
    Map.get_lazy(@section_labels, key, fn ->
      "Documentation: " <> (key |> String.replace("-", " ") |> String.capitalize())
    end)
  end

  defp page_line(page) do
    url = Tuist.Environment.app_url(path: Paths.markdown_path_from_slug(page.slug))
    link(page.title, url, page.description)
  end

  defp link_section(title, pages) do
    ["## #{title}", ""] ++
      Enum.map(pages, fn {path, description} ->
        target = MarketingMarkdown.alternate_path(path) || path
        link(page_title(path), Tuist.Environment.app_url(path: target), description)
      end) ++ [""]
  end

  defp page_title("/"), do: "Tuist"

  defp page_title(path) do
    path
    |> String.trim_leading("/")
    |> String.replace(".xml", "")
    |> String.split("-")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp link(title, url, nil), do: "- [#{title}](#{url})"
  defp link(title, url, ""), do: link(title, url, nil)
  defp link(title, url, description), do: "- [#{title}](#{url}): #{description}"
end
