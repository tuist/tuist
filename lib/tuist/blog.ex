defmodule Tuist.Blog do
  @moduledoc ~S"""
  This module loads the blog posts and authors to be used in the blog section of the marketing website.
  The content is included in the compiled Erlang binary.
  """
  alias Tuist.Blog.Post
  alias Tuist.Blog.PostParser

  use NimblePublisher,
    build: Post,
    from: Application.app_dir(:tuist, "priv/blog/**/*.md"),
    as: :posts,
    parser: PostParser,
    highlighters: [],
    earmark_options: [
      postprocessor: &Tuist.Blog.ASTPostProcessor.process/1
    ]

  @posts @posts |> Enum.reverse()
  @categories @posts |> Enum.map(& &1.category) |> Enum.uniq()

  def get_posts, do: @posts
  def get_categories, do: @categories
  def get_post_author(post), do: get_authors()[post.author]

  def get_authors() do
    %{
      "vytis" => %{
        "role" => "Automation at Neko Health",
        "name" => "Vytis",
        "x_handle" => "vytis0",
        "github_handle" => "vytis"
      },
      "trendyol" => %{
        "role" => "E-commerce platform",
        "name" => "Trendyol",
        "x_handle" => "Trendyol",
        "github_handle" => "Trendyol"
      },
      "pepicrft" => %{
        "role" => "Tuist CEO",
        "name" => "Pedro Piñera",
        "x_handle" => "pepicrft",
        "mastodon_url" => "https://mastodon.social/@pepicrft",
        "github_handle" => "pepicrft"
      },
      "ollieatkinson" => %{
        "role" => "Senior software engineer at Monzo",
        "name" => "Oliver Atkinson",
        "github_handle" => "ollieatkinson"
      },
      "natanrolnik" => %{
        "role" => "iOS Platform engineer at Monday.com",
        "name" => "Natan Rolnik",
        "x_handle" => "natanrolnik",
        "mastodon_url" => "https://mastodon.social/@natanrolnik",
        "github_handle" => "natanrolnik"
      },
      "kwridan" => %{
        "role" => "Software engineer at Bloomberg",
        "name" => "Kas Wridan",
        "x_handle" => "kwridan",
        "github_handle" => "kwridan"
      },
      "fortmarek" => %{
        "role" => "Tuist CTO",
        "name" => "Marek Fořt",
        "x_handle" => "marekfort",
        "mastodon_url" => "https://mastodon.social/@marekfort@mastodon.online",
        "github_handle" => "fortmarek"
      },
      "cpisciotta" => %{
        "role" => "Software engineer at Audible",
        "name" => "Charles Pisciotta",
        "x_handle" => "CharlesP000",
        "mastodon_url" => "https://mastodon.social/@charlespisciotta",
        "github_handle" => "cpisciotta"
      }
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
            get_blog_post_structured_markup_data(post) |> Map.merge(%{"position" => index + 1})
          end)
      },
      "name" => "Tuist's blog",
      "description" => "Read engaging stories and expert insights.",
      "publisher" => %{
        "@type" => "Organization",
        "name" => "Tuist",
        "logo" => %{
          "@type" => "ImageObject",
          "url" => Tuist.Environment.app_url(path: "/images/open-graph.png")
        }
      }
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
        "name" => "Author's Name",
        "url" => "https://github.com/#{get_post_author(post)["github_handle"]}"
      },
      "publisher" => %{
        "@type" => "Organization",
        "name" => "Tuist",
        "logo" => %{
          "@type" => "ImageObject",
          "url" => Tuist.Environment.app_url(path: "/images/open-graph.png")
        }
      },
      "datePublished" => Timex.format!(post.date, "{ISO:Extended}"),
      "dateModified" => Timex.format!(post.date, "{ISO:Extended}"),
      "articleBody" => post.excerpt
    }
  end
end
