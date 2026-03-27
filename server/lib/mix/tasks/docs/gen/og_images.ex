defmodule Mix.Tasks.Docs.Gen.OgImages do
  @moduledoc """
  Generates open graph images for all documentation pages using Carta and BrowseServo.
  """
  use Mix.Task
  use Boundary, classify_to: Tuist.Mix

  alias Tuist.Docs
  alias Tuist.Docs.Sidebar

  @pool Tuist.Docs.OgImagePool

  def run(_args) do
    Mix.Task.run("app.start")

    output_dir =
      :tuist |> Application.app_dir("priv") |> Path.join("static/docs/images/og/generated")

    File.mkdir_p!(output_dir)

    fonts_dir =
      :tuist |> Application.app_dir("priv") |> Path.join("static/fonts")

    logo_path =
      :tuist |> Application.app_dir("priv") |> Path.join("static/docs/images/logo.webp")

    Application.put_env(:browse_servo, :default_pool, @pool)
    Application.put_env(:browse_servo, :pools, [{@pool, pool_size: 2}])

    children = BrowseServo.children()
    Enum.each(children, fn spec -> {:ok, _} = Supervisor.start_child(Tuist.Supervisor, spec) end)

    category_map = build_category_map()

    pages = Docs.pages()

    Enum.each(pages, fn page ->
      slug = page.slug
      en_slug = slug |> String.replace(~r{^/[^/]+/}, "/") |> String.trim_leading("/")
      filename = en_slug |> String.replace("/", "-") |> then(&"#{&1}.jpg")
      image_path = Path.join(output_dir, filename)

      category = Map.get(category_map, slug, "Docs")

      html =
        Tuist.Docs.OgImage.render_html(
          title: page.title,
          description: page.description,
          category: category,
          fonts_dir: fonts_dir,
          logo_path: logo_path
        )

      IO.puts("Generating OG image for '#{page.title}' at #{Path.relative_to(image_path, File.cwd!())}")

      case Carta.render(@pool, html, width: 1920, height: 1080, quality: 95) do
        {:ok, jpeg_binary} ->
          File.write!(image_path, jpeg_binary)

        {:error, reason} ->
          IO.warn("Failed to generate OG image for #{slug}: #{inspect(reason)}")
      end
    end)
  end

  defp build_category_map do
    Sidebar.tree()
    |> Enum.flat_map(fn group ->
      collect_slugs_with_category(group.label || "Docs", group.items)
    end)
    |> Map.new()
  end

  defp collect_slugs_with_category(category, items) do
    Enum.flat_map(items, fn item ->
      own =
        if item.slug do
          [{item.slug, category}]
        else
          []
        end

      children = collect_slugs_with_category(category, item.items)
      own ++ children
    end)
  end
end
