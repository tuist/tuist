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
      data -> Enum.map(data, &JSON.encode!/1)
    end
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
              "text" => answer |> Floki.parse_fragment() |> Floki.text()
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
      "offers" =>
        Enum.map(plans, fn plan ->
          %{
            "@type" => "Offer",
            "name" => "Tuist #{plan.name}",
            "url" => Tuist.Environment.app_url(path: ~p"/pricing"),
            "priceCurrency" => "USD",
            "price" => if(plan.price == "Free", do: "0.00", else: String.trim_leading(plan.price, "$")),
            "description" => plan.description,
            "availability" => "https://schema.org/InStock",
            "priceValidUntil" => "2025-12-31",
            "image" => Tuist.Environment.app_url(path: "/images/open-graph/squared.png")
          }
        end)
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
      "inLanguage" => Gettext.get_locale(TuistWeb.Gettext)
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
          "Tuist is build infrastructure for productive teams. It integrates into existing build toolchains to share a binary cache across machines and CI, run only the tests a change can affect, track flaky tests, and share app previews from a URL."
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
  """
  def get_feature_structured_data(name, description, path) do
    %{
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
      },
      "offers" => %{
        "@type" => "Offer",
        "price" => "0",
        "priceCurrency" => "USD",
        "url" => Tuist.Environment.app_url(path: ~p"/pricing")
      }
    }
  end

  @doc """
  Assigns the `SoftwareApplication` and breadcrumb markup a product page needs.

  `path` is the unlocalized page path; the locale in scope decides the URLs the
  nodes point at, so the markup agrees with the page's canonical URL.
  """
  def assign_feature_structured_data(target, name, description, path) do
    locale = Gettext.get_locale(TuistWeb.Gettext)
    localized_path = Localization.localized_href(path, locale)

    put_structured_data(target, [
      get_feature_structured_data(name, description, localized_path),
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

  def get_blog_structured_markup_data(posts) do
    %{
      "@context" => "https://schema.org",
      "@type" => "CollectionPage",
      "mainEntityOfPage" => %{
        "@type" => "ItemList",
        "itemListElement" =>
          posts
          |> Enum.with_index()
          |> Enum.map(fn {post, index} ->
            post |> get_blog_post_structured_markup_data() |> Map.put("position", index + 1)
          end)
      },
      "name" => dgettext("marketing", "Tuist's blog"),
      "description" => dgettext("marketing", "Read engaging stories and expert insights."),
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
      "image" => if(is_nil(post.image_url), do: [], else: [post.image_url]),
      "author" =>
        maybe_put(
          %{"@type" => "Person", "name" => Blog.get_post_author_name(post)},
          "url",
          Blog.get_post_author_url(post)
        ),
      "publisher" => StructuredMarkup.get_organization_structured_data(),
      "datePublished" => Timex.format!(post.date, "{ISO:Extended}"),
      "dateModified" => Timex.format!(post.date, "{ISO:Extended}"),
      "articleBody" => post.excerpt
    }
  end

  def get_changelog_structured_data(entries) do
    %{
      "@context" => "https://schema.org",
      "@type" => "ItemList",
      "name" => dgettext("marketing", "Changelog"),
      "description" => dgettext("marketing", "Stay updated with the latest changes and improvements in Tuist."),
      "publisher" => StructuredMarkup.get_organization_structured_data(),
      "itemListElement" =>
        entries
        |> Enum.with_index()
        |> Enum.map(fn {entry, index} ->
          %{
            "@type" => "ListItem",
            "position" => index + 1,
            "item" => %{
              "@type" => "Article",
              "headline" => entry.title,
              "datePublished" => Timex.format!(entry.date, "{ISO:Extended}"),
              "url" => Tuist.Environment.app_url(path: "/changelog/#{entry.id}"),
              "articleSection" => entry.category,
              "description" => entry.body
            }
          }
        end)
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

    case_study_url =
      case_study
      |> Customers.case_study_href()
      |> Localization.localized_href(locale)
      |> absolute_url()

    %{
      "@context" => "https://schema.org",
      "@type" => "Article",
      "mainEntityOfPage" => %{
        "@type" => "WebPage",
        "@id" => case_study_url
      },
      "headline" => case_study.title,
      "description" => case_study.excerpt,
      "image" => Tuist.Environment.app_url(path: case_study.og_image_path),
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
      "mainEntityOfPage" => %{
        "@type" => "ItemList",
        "itemListElement" =>
          cases
          |> Enum.with_index()
          |> Enum.map(fn {case_study, index} ->
            case_study
            |> get_case_study_article_structured_data(locale)
            |> Map.put("position", index + 1)
          end)
      },
      "name" => dgettext("marketing", "Tuist Customers"),
      "description" => dgettext("marketing", "Learn how teams use Tuist to scale their iOS development."),
      "publisher" => StructuredMarkup.get_organization_structured_data()
    }
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
