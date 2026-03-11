defmodule Noora.Icon do
  @moduledoc """
  Icons in use across the Noora design system.

  ## Usage

  The module exposes all icons in two ways:
  1. As a function of the shape `<.{icon_name} />`
  2. As an `icon` component that takes a `name` attribute.

  ```elixir
  <.mail />
  <.icon name="mail" />
  ```

  ## Adding an icon

  Icons are automatically read and generated from the `icons` folder. To add an icon, simply add a SVG file to the folder. File names are
  required to be alphanumeric. Hyphens in the file name are automatically substituted to underscores.
  """
  use Phoenix.Component

  @icons_path Path.join(File.cwd!(), "lib/noora/icons")
  @external_resource @icons_path

  for file <- File.ls!(@icons_path),
      Path.extname(file) == ".svg" do
    icon_name =
      file
      |> Path.basename(".svg")
      |> String.replace("-", "_")

    file_path = Path.join(@icons_path, file)
    content = File.read!(file_path)

    def unquote(String.to_atom(icon_name))(assigns) do
      assigns = assign(assigns, :content, unquote(content))

      ~H"""
      {Phoenix.HTML.raw(@content)}
      """
    end

    def icon(%{name: unquote(icon_name)} = assigns) do
      assigns = assign(assigns, :content, unquote(content))

      ~H"""
      {Phoenix.HTML.raw(@content)}
      """
    end
  end
end
