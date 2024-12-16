defmodule Mix.Tasks.Marketing.Gen.OgImages do
  @moduledoc ~S"""
  This task generates the open graph images dynamically for all the marketing routes
  """
  use Mix.Task
  use Boundary, classify_to: Tuist.Mix

  def run(_args) do
    og_images_directory =
      Application.app_dir(:tuist, "priv") |> Path.join("static/marketing/images/og/generated")

    generate_posts_og_images(og_images_directory)
    generate_pages_og_images(og_images_directory)
  end

  defp generate_pages_og_images(og_images_directory) do
    dynamic_pages = Tuist.Marketing.Pages.get_pages()

    dynamic_pages
    |> Enum.each(fn page ->
      Tuist.Marketing.OpenGraph.generate_og_image(
        page.title,
        Path.join(og_images_directory, "#{String.split(page.slug, "/") |> List.last()}.jpg")
      )
    end)

    Tuist.Marketing.OpenGraph.generate_og_image(
      "About us",
      Path.join(og_images_directory, "about.jpg")
    )

    Tuist.Marketing.OpenGraph.generate_og_image(
      "Swift Stories Newsletter",
      Path.join(og_images_directory, "swift-stories.jpg")
    )
  end

  defp generate_posts_og_images(og_images_directory) do
    Tuist.Marketing.Blog.get_posts()
    |> Enum.each(fn post ->
      image_path = Path.join(og_images_directory, "#{post.slug}.jpg")

      IO.puts(
        "Generating OG image for '#{post.title}' at #{Path.relative_to(image_path, File.cwd!())}"
      )

      File.mkdir_p!(Path.dirname(image_path))

      Tuist.Marketing.OpenGraph.generate_og_image(
        post.title,
        image_path
      )
    end)
  end
end
