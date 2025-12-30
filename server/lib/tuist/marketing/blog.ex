defmodule Tuist.Marketing.Blog do
  @moduledoc ~S"""
  This module loads the blog posts and authors to be used in the blog section of the marketing website.
  The content is included in the compiled Erlang binary.
  """
  use NimblePublisher,
    build: Tuist.Marketing.Blog.Post,
    from: Application.app_dir(:tuist, "priv/marketing/blog/**/*.md"),
    as: :posts,
    parser: Tuist.Marketing.Blog.PostParser,
    highlighters: [],
    earmark_options: [
      smartypants: false,
      postprocessor: &Tuist.Earmark.ASTProcessor.process/1
    ]

  @posts Enum.reverse(@posts)
  @categories @posts |> Enum.map(& &1.category) |> Enum.uniq()

  def get_posts, do: @posts
  def get_categories, do: @categories
  def get_post_author(post), do: get_authors()[post.author]

  def get_post_author_name(post), do: post |> get_post_author() |> author_name_or_fallback(post.author)

  @doc """
  Returns the image URL for a blog post, using the og_image_path if available,
  otherwise falling back to the generated OG image.
  """
  def get_post_image_url(post) do
    if post.og_image_path do
      Tuist.Environment.app_url(
        path: post.og_image_path,
        marketing: true
      )
    else
      Tuist.Environment.app_url(
        path: "/marketing/images/og/generated#{post.slug}.jpg",
        marketing: true
      )
    end
  end

  @doc """
  Processes blog post content to extract components and HTML chunks.
  """
  def process_content(content) do
    Tuist.Marketing.BlogContentProcessor.process_content(content)
  end

  def get_authors do
    %{
      "silvia" => %{
        "role" => "Senior Product Designer at Guinda Studio",
        "name" => "Silvia",
        "image_href" => "/marketing/images/authors/silvia.jpeg"
      },
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
        "github_handle" => "pepicrft",
        "fediverse_username" => "@pepicrft@mastodon.social"
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
        "github_handle" => "fortmarek",
        "fediverse_username" => "@marekfort@mastodon.online"
      },
      "cpisciotta" => %{
        "role" => "Software engineer at Audible",
        "name" => "Charles Pisciotta",
        "x_handle" => "CharlesP000",
        "mastodon_url" => "https://mastodon.social/@charlespisciotta",
        "github_handle" => "cpisciotta"
      },
      "aatakankarsli" => %{
        "role" => "Senior Developer at Trendyol",
        "name" => "Atakan Karslı",
        "x_handle" => "AtakanKarsli_",
        "github_handle" => "atakankarsli",
        "image_href" => "/marketing/images/authors/aatakankarsli.jpg"
      },
      "ajkolean" => %{
        "role" => "Principal iOS Engineer at Fundrise",
        "name" => "Andrew Kolean",
        "github_handle" => "ajkolean",
        "image_href" => "/marketing/images/authors/ajkolean.jpg"
      },
      "asmitbm" => %{
        "role" => "Designer at Tuist",
        "name" => " Asmit Malakannawar ",
        "mastodon_url" => "https://mastodon.social/@asmitbm",
        "github_handle" => "asmitbm",
        "fediverse_username" => "@asmitbm@mastodon.online"
      },
      "cschmatzler" => %{
        "role" => "Software Engineer at Tuist",
        "name" => "Christoph Schmatzler",
        "x_handle" => "cschmatzler",
        "github_handle" => "cschmatzler",
        "fediverse_username" => "@cschmatzler@fosstodon.org"
      }
    }
  end

  defp author_name_or_fallback(nil, fallback), do: fallback || "Tuist"
  defp author_name_or_fallback(author, _fallback), do: author["name"]
end
