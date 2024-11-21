defmodule Mix.Tasks.Marketing.GenerateOgImages do
  @moduledoc ~S"""
  This task generates the open graph images dynamically for all the marketing routes
  """
  use Mix.Task

  def run(_args) do
    og_images_directory =
      Application.app_dir(:tuist, "priv") |> Path.join("static/marketing/images/og/generated")

    generate_posts_og_images(og_images_directory)
    generate_pages_og_images(og_images_directory)
  end

  defp generate_pages_og_images(og_images_directory) do
    Tuist.Marketing.OpenGraph.generate_og_image(
      "Terms of service",
      Path.join(og_images_directory, "terms.jpg")
    )

    Tuist.Marketing.OpenGraph.generate_og_image(
      "Privacy policy",
      Path.join(og_images_directory, "privacy.jpg")
    )

    Tuist.Marketing.OpenGraph.generate_og_image(
      "Imprint",
      Path.join(og_images_directory, "imprint.jpg")
    )

    Tuist.Marketing.OpenGraph.generate_og_image(
      "Cookie policy",
      Path.join(og_images_directory, "cookies.jpg")
    )

    Tuist.Marketing.OpenGraph.generate_og_image(
      "About us",
      Path.join(og_images_directory, "about.jpg")
    )
  end

  defp generate_posts_og_images(og_images_directory) do
    Tuist.Marketing.Blog.get_posts()
    |> Enum.each(fn post ->
      IO.puts("Generating OG image for blog post: #{post.title}")
      image_path = Path.join(og_images_directory, "#{post.slug}.jpg")
      File.mkdir_p!(Path.dirname(image_path))

      Tuist.Marketing.OpenGraph.generate_og_image(
        post.title,
        image_path
      )
    end)
  end
end
