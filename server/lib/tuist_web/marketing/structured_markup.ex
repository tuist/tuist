defmodule TuistWeb.Marketing.StructuredMarkup do
  @moduledoc """
  A set of utilities for generating structured markup data.
  - https://developers.google.com/search/docs/appearance/structured-data/intro-structured-data
  """

  use Gettext, backend: TuistWeb.Gettext

  use Phoenix.VerifiedRoutes,
    endpoint: TuistWeb.Endpoint,
    router: TuistWeb.Router,
    statics: TuistWeb.static_paths()

  alias Phoenix.LiveView.Socket
  alias Tuist.Marketing.Blog
  alias Tuist.Marketing.Customers
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Marketing.Localization
  alias TuistWeb.Marketing.StructuredMarkup

  def assign_structured_data(%Plug.Conn{} = conn, data) do
    structured_data = conn.assigns[:head_structured_data] || []

    structured_data =
      case data do
        data when is_list(data) ->
          structured_data ++ data

        _ ->
          structured_data ++ [data]
      end

    Plug.Conn.assign(conn, :head_structured_data, structured_data)
  end

  def assign_structured_data(%Socket{} = socket, data) do
    structured_data = socket.assigns[:head_structured_data] || []

    structured_data =
      case data do
        data when is_list(data) ->
          structured_data ++ data

        _ ->
          structured_data ++ [data]
      end

    Phoenix.Component.assign(socket, :head_structured_data, structured_data)
  end

  @doc """
  Replaces the page's structured data instead of adding to it.

  `assign_structured_data/2` appends, which is what a controller wants when it
  chains several nodes for one response. A LiveView's `handle_params/3` runs
  again on every live patch, so appending there would grow the socket's list by
  a page's worth of nodes on every in-place navigation. LiveViews should build
  their whole list in one call and use this.
  """
  def put_structured_data(%Plug.Conn{} = conn, data) do
    Plug.Conn.assign(conn, :head_structured_data, List.wrap(data))
  end

  def put_structured_data(%Socket{} = socket, data) do
    Phoenix.Component.assign(socket, :head_structured_data, List.wrap(data))
  end

  @doc """
  Marks the page as an article for Open Graph consumers.

  The default `og:type` is `website`, which tells crawlers and social cards
  nothing about when a post was written or who wrote it. Anything with a
  publication date should call this so `article:published_time` and friends are
  emitted alongside the JSON-LD.

  `:author_url` is a profile URL, not a display name: Open Graph types
  `article:author` as a profile, so a bare name is dropped by consumers that
  enforce it. The readable name still reaches crawlers through the JSON-LD.
  """
  def assign_article_head_meta(target, opts) do
    published_at = Keyword.get(opts, :published_at)

    target
    |> assign_head(:head_og_type, "article")
    |> assign_head(:head_site_name, "Tuist")
    |> assign_head(:head_published_time, format_iso8601(published_at))
    |> assign_head(:head_modified_time, format_iso8601(Keyword.get(opts, :modified_at) || published_at))
    |> assign_head(:head_article_author, Keyword.get(opts, :author_url))
  end

  defp assign_head(target, _key, nil), do: target
  defp assign_head(%Plug.Conn{} = conn, key, value), do: Plug.Conn.assign(conn, key, value)

  defp assign_head(%Socket{} = socket, key, value) do
    Phoenix.Component.assign(socket, key, value)
  end

  # `article:*` takes a datetime, so a date-only value is widened to midnight UTC
  # rather than emitted bare.
  defp format_iso8601(nil), do: nil
  defp format_iso8601(%DateTime{} = date_time), do: DateTime.to_iso8601(date_time)
  defp format_iso8601(%NaiveDateTime{} = naive), do: NaiveDateTime.to_iso8601(naive)

  defp format_iso8601(%Date{} = date) do
    date |> DateTime.new!(~T[00:00:00], "Etc/UTC") |> DateTime.to_iso8601()
  end

  def get_breadcrumbs_structured_data(breadcrumbs) do
    %{
      "@context" => "https://schema.org",
      "@type" => "BreadcrumbList",
      "itemListElement" =>
        breadcrumbs
        # Start index at 1 since breadcrumb positions must start at 1 per Schema.org spec
        |> Enum.with_index(1)
        |> Enum.map(fn {{name, url}, position} ->
          %{
            "@type" => "ListItem",
            "position" => position,
            "name" => name,
            "item" => url
          }
        end)
    }
  end

  def get_json_serialized_structured_data(assigns) do
    structured_data = assigns[:head_structured_data]

    case structured_data do
      nil -> []
      data -> Enum.map(data, &encode_for_script_tag/1)
    end
  end

  # The JSON is written raw into a <script> element, which ends at the first
  # `</script>` no matter where it sits, and changelog and blog text can quote
  # HTML. `<` only ever appears inside JSON strings, so escaping it as \u003c
  # keeps the value identical for parsers while the tag can no longer close early.
  defp encode_for_script_tag(data) do
    data |> JSON.encode!() |> String.replace("<", "\\u003c")
  end

  def get_faq_structured_data(faqs) do
    %{
      "@context" => "https://schema.org",
      "@type" => "FAQPage",
      "mainEntity" =>
        Enum.map(faqs, fn {question, answer} ->
          %{
            "@type" => "Question",
            "name" => question,
            "acceptedAnswer" => %{
              "@type" => "Answer",
              "text" => answer |> Floki.parse_fragment!() |> Floki.text()
            }
          }
        end)
    }
  end

  def get_pricing_plans_structured_data(plans) do
    %{
      "@context" => "https://schema.org",
      "@type" => "Product",
      "name" => "Tuist",
      "description" =>
        dgettext(
          "marketing",
          "Tuist is designed to grow with you. Only add a card if you need more than the free tier limits or dedicated support."
        ),
      "brand" => get_organization_structured_data(),
      "image" => Tuist.Environment.app_url(path: "/images/open-graph/squared.png"),
      # Display prices are localized labels, not fixed totals. Only Air has a
      # fixed price (free); Pro is metered above allowances and Enterprise is
      # negotiated, so neither can be an `Offer`, which search engines reject
      # without a `price`. The range's floor is the one price we can state.
      "offers" => %{
        "@type" => "AggregateOffer",
        "lowPrice" => "0.00",
        "priceCurrency" => "USD",
        "offerCount" => length(plans),
        "url" => Tuist.Environment.app_url(path: ~p"/pricing"),
        "availability" => "https://schema.org/InStock"
      }
    }
  end

  def get_testimonials_structured_data(testimonials) do
    testimonials
    |> Enum.map(fn group ->
      Enum.map(group, fn testimonial ->
        %{
          "@context" => "http://schema.org",
          "@type" => "Review",
          "author" => %{
            "@type" => "Person",
            "name" => testimonial.author,
            "url" => testimonial.author_link,
            "image" => Tuist.Environment.app_url(path: testimonial.avatar_src)
          },
          "reviewBody" => testimonial.body |> Floki.parse_fragment() |> Floki.text(),
          "reviewRating" => %{
            "@type" => "Rating",
            "ratingValue" => 5
          },
          "publisher" => get_organization_structured_data(),
          "itemReviewed" => %{
            "@type" => "Product",
            "name" => "Tuist",
            "url" => Tuist.Environment.app_url(),
            "aggregateRating" => %{
              "@type" => "AggregateRating",
              "ratingValue" => 5,
              "reviewCount" => 1
            }
          }
        }
      end)
    end)
    |> List.flatten()
  end

  def get_organization_structured_data do
    %{
      "@context" => "https://schema.org",
      "@type" => "Organization",
      "name" => "Tuist",
      "description" =>
        dgettext(
          "marketing",
          "Tuist is build infrastructure for engineering teams and coding agents."
        ),
      "url" => Tuist.Environment.app_url(),
      "logo" => Tuist.Environment.app_url(path: "/images/tuist_social.jpeg"),
      "sameAs" => [
        "https://fosstodon.org/@tuist",
        "https://bsky.app/profile/tuist.dev",
        "https://www.linkedin.com/company/tuistio",
        "https://github.com/tuist"
      ]
    }
  end

  def get_website_structured_data do
    %{
      "@context" => "https://schema.org",
      "@type" => "WebSite",
      "name" => "Tuist",
      "url" => Tuist.Environment.app_url(),
      "publisher" => get_organization_structured_data(),
      "inLanguage" => TuistWeb.Locale.language_tag(Gettext.get_locale(TuistWeb.Gettext))
    }
  end

  @doc """
  Describes Tuist itself so assistants asking "what is Tuist" get the category,
  the platforms it targets, and the pricing model from one node instead of
  inferring them from prose.
  """
  def get_software_application_structured_data do
    %{
      "@context" => "https://schema.org",
      "@type" => "SoftwareApplication",
      "name" => "Tuist",
      "url" => Tuist.Environment.app_url(),
      "applicationCategory" => "DeveloperApplication",
      "applicationSubCategory" => "Build automation",
      "operatingSystem" => "macOS, Linux",
      "description" =>
        dgettext(
          "marketing",
          "Tuist is build infrastructure for engineering teams and coding agents."
        ),
      "image" => Tuist.Environment.app_url(path: "/images/open-graph/squared.png"),
      "publisher" => get_organization_structured_data(),
      "isAccessibleForFree" => true,
      "offers" => %{
        "@type" => "Offer",
        "price" => "0",
        "priceCurrency" => "USD",
        "url" => Tuist.Environment.app_url(path: ~p"/pricing")
      },
      "softwareHelp" => %{
        "@type" => "CreativeWork",
        "url" => Tuist.Environment.app_url(path: "/en/docs")
      }
    }
  end

  @doc """
  Marks a product page up as the feature it documents. `path` is the localized
  page path so the node's identity matches the page's canonical URL.

  Pass `free: false` for features billed outside the free tier, such as
  Compute, so the node does not claim a $0 offer.
  """
  def get_feature_structured_data(name, description, path, opts \\ []) do
    node = %{
      "@context" => "https://schema.org",
      "@type" => "SoftwareApplication",
      "name" => "Tuist #{name}",
      "url" => Tuist.Environment.app_url(path: path),
      "applicationCategory" => "DeveloperApplication",
      "operatingSystem" => "macOS, Linux",
      "description" => description,
      "publisher" => get_organization_structured_data(),
      "isPartOf" => %{
        "@type" => "SoftwareApplication",
        "name" => "Tuist",
        "url" => Tuist.Environment.app_url()
      }
    }

    if Keyword.get(opts, :free, true) do
      Map.put(node, "offers", %{
        "@type" => "Offer",
        "price" => "0",
        "priceCurrency" => "USD",
        "url" => Tuist.Environment.app_url(path: ~p"/pricing")
      })
    else
      node
    end
  end

  @doc """
  Assigns the `SoftwareApplication` and breadcrumb markup a product page needs.

  `path` is the unlocalized page path; the locale in scope decides the URLs the
  nodes point at, so the markup agrees with the page's canonical URL. `opts`
  are passed to `get_feature_structured_data/4`.
  """
  def assign_feature_structured_data(target, name, description, path, opts \\ []) do
    locale = Gettext.get_locale(TuistWeb.Gettext)
    localized_path = Localization.localized_href(path, locale)

    put_structured_data(target, [
      get_feature_structured_data(name, description, localized_path, opts),
      get_breadcrumbs_structured_data([
        {"Tuist", Tuist.Environment.app_url(path: Localization.localized_href("/", locale))},
        {name, Tuist.Environment.app_url(path: localized_path)}
      ])
    ])
  end

  @doc """
  Marks a documentation page up as a `TechArticle`. Docs are the largest body of
  content on the site and carried no markup at all, which left assistants
  quoting them with no attribution back to Tuist.
  """
  def get_documentation_structured_data(title, description, path) do
    url = Tuist.Environment.app_url(path: path)

    maybe_put(
      %{
        "@context" => "https://schema.org",
        "@type" => "TechArticle",
        "mainEntityOfPage" => %{"@type" => "WebPage", "@id" => url},
        "headline" => title,
        "url" => url,
        "publisher" => get_organization_structured_data(),
        "isPartOf" => %{"@type" => "WebSite", "name" => "Tuist", "url" => Tuist.Environment.app_url()}
      },
      "description",
      description
    )
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # Listing pages point at their entries instead of embedding them: each entry
  # carries its full markup on its own page, and inlining all of them made the
  # blog and changelog ship hundreds of kilobytes of JSON-LD. `position`
  # belongs on the `ListItem`, not on the entry.
  defp item_list(entries) do
    %{
      "@type" => "ItemList",
      "numberOfItems" => length(entries),
      "itemListElement" =>
        entries
        |> Enum.with_index(1)
        |> Enum.map(fn {{name, url}, position} ->
          %{"@type" => "ListItem", "position" => position, "name" => name, "url" => url}
        end)
    }
  end

  def get_blog_structured_markup_data(posts) do
    %{
      "@context" => "https://schema.org",
      "@type" => "CollectionPage",
      "mainEntity" => item_list(Enum.map(posts, &{&1.title, Tuist.Environment.app_url(path: &1.slug)})),
      "name" => dgettext("marketing", "Tuist's blog"),
      "description" =>
        dgettext(
          "marketing",
          "Engineering articles from Tuist on build infrastructure, developer workflows, and coding agents, with product updates and technical decisions."
        ),
      "publisher" => StructuredMarkup.get_organization_structured_data()
    }
  end

  def get_blog_post_structured_markup_data(post) do
    %{
      "@context" => "https://schema.org",
      "@type" => "BlogPosting",
      "mainEntityOfPage" => %{
        "@type" => "WebPage",
        "@id" => Tuist.Environment.app_url(path: post.slug)
      },
      "headline" => post.title,
      "description" => post.excerpt,
      "image" => [blog_post_image_url(post)],
      "author" =>
        maybe_put(
          %{"@type" => "Person", "name" => Blog.get_post_author_name(post)},
          "url",
          Blog.get_post_author_url(post)
        ),
      "publisher" => StructuredMarkup.get_organization_structured_data(),
      "datePublished" => Timex.format!(post.date, "{ISO:Extended}"),
      "dateModified" => Timex.format!(post.date, "{ISO:Extended}")
    }
  end

  defp blog_post_image_url(post) do
    case post.image_url || post.og_image_path do
      nil ->
        Tuist.Environment.app_url(
          path: OpenGraph.image_path(:marketing_text, title: post.title),
          marketing: true
        )

      "http" <> _rest = url ->
        url

      path ->
        Tuist.Environment.app_url(path: path, marketing: true)
    end
  end

  def get_changelog_structured_data(entries) do
    %{
      "@context" => "https://schema.org",
      "@type" => "CollectionPage",
      "mainEntity" => item_list(Enum.map(entries, &{&1.title, Tuist.Environment.app_url(path: "/changelog/#{&1.id}")})),
      "name" => dgettext("marketing", "Changelog"),
      "description" => dgettext("marketing", "Stay updated with the latest changes and improvements in Tuist."),
      "publisher" => StructuredMarkup.get_organization_structured_data()
    }
  end

  def get_changelog_entry_structured_data(entry) do
    %{
      "@context" => "https://schema.org",
      "@type" => "Article",
      "mainEntityOfPage" => %{
        "@type" => "WebPage",
        "@id" => Tuist.Environment.app_url(path: "/changelog/#{entry.id}")
      },
      "headline" => entry.title,
      "articleSection" => entry.category,
      "publisher" => StructuredMarkup.get_organization_structured_data(),
      "datePublished" => Timex.format!(entry.date, "{ISO:Extended}"),
      "dateModified" => Timex.format!(entry.date, "{ISO:Extended}")
    }
  end

  def get_case_study_article_structured_data(case_study, locale \\ "en") do
    date_time = DateTime.new!(case_study.date, ~T[00:00:00], "Etc/UTC")
    case_study_url = case_study_url(case_study, locale)

    %{
      "@context" => "https://schema.org",
      "@type" => "Article",
      "mainEntityOfPage" => %{
        "@type" => "WebPage",
        "@id" => case_study_url
      },
      "headline" => case_study.title,
      "description" => case_study.excerpt,
      "image" => Tuist.Environment.app_url(path: TuistWeb.Marketing.MarketingCustomerCovers.og_image_path(case_study)),
      "author" => %{
        "@type" => "Organization",
        "name" => case_study.company,
        "url" => case_study.url
      },
      "publisher" => StructuredMarkup.get_organization_structured_data(),
      "datePublished" => Timex.format!(date_time, "{ISO:Extended}"),
      "dateModified" => Timex.format!(date_time, "{ISO:Extended}"),
      "articleBody" => case_study.excerpt
    }
  end

  def get_case_studies_structured_data(cases, locale \\ "en") do
    %{
      "@context" => "https://schema.org",
      "@type" => "CollectionPage",
      "mainEntity" =>
        item_list(
          Enum.map(cases, fn case_study ->
            {case_study.title, case_study_url(case_study, locale)}
          end)
        ),
      "name" => dgettext("marketing", "Tuist Customers"),
      "description" => dgettext("marketing", "Learn how teams use Tuist to scale their iOS development."),
      "publisher" => StructuredMarkup.get_organization_structured_data()
    }
  end

  defp case_study_url(case_study, locale) do
    case_study
    |> Customers.case_study_href()
    |> Localization.localized_href(locale)
    |> absolute_url()
  end

  defp absolute_url(href) do
    uri = URI.parse(href)

    if is_nil(uri.scheme) and is_nil(uri.host) do
      Tuist.Environment.app_url(path: href)
    else
      href
    end
  end
end
