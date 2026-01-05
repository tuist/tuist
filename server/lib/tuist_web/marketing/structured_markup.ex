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

  alias Tuist.Marketing.Blog
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

  def assign_structured_data(%Phoenix.LiveView.Socket{} = socket, data) do
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
      data -> Enum.map(data, &Jason.encode!/1)
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
        "https://www.linkedin.com/company/tuistio"
      ]
    }
  end

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
      "author" => %{
        "@type" => "Person",
        "name" => Blog.get_post_author(post)["name"],
        "url" => "https://github.com/#{Blog.get_post_author(post)["github_handle"]}"
      },
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
              "url" => Tuist.Environment.app_url(path: "/changelog##{entry.id}"),
              "articleSection" => entry.category,
              "description" => entry.body
            }
          }
        end)
    }
  end

  def get_case_study_article_structured_data(case_study) do
    date_time = DateTime.new!(case_study.date, ~T[00:00:00], "Etc/UTC")

    %{
      "@context" => "https://schema.org",
      "@type" => "Article",
      "mainEntityOfPage" => %{
        "@type" => "WebPage",
        "@id" => Tuist.Environment.app_url(path: case_study.slug)
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

  def get_case_studies_structured_data(cases) do
    %{
      "@context" => "https://schema.org",
      "@type" => "CollectionPage",
      "mainEntityOfPage" => %{
        "@type" => "ItemList",
        "itemListElement" =>
          cases
          |> Enum.with_index()
          |> Enum.map(fn {case_study, index} ->
            case_study |> get_case_study_article_structured_data() |> Map.put("position", index + 1)
          end)
      },
      "name" => dgettext("marketing", "Tuist Customers"),
      "description" => dgettext("marketing", "Learn how teams use Tuist to scale their iOS development."),
      "publisher" => StructuredMarkup.get_organization_structured_data()
    }
  end
end
