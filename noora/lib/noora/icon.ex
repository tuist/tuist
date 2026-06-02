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
    @external_resource file_path
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

  @icon_paths (for file <- File.ls!(@icons_path),
                   Path.extname(file) == ".svg",
                   into: %{} do
                 name = file |> Path.basename(".svg") |> String.replace("-", "_")

                 d =
                   @icons_path
                   |> Path.join(file)
                   |> File.read!()
                   |> then(&Regex.scan(~r/\bd="([^"]*)"/, &1))
                   |> Enum.map_join(" ", fn [_, path] -> path end)

                 {name, d}
               end)

  @doc """
  Returns the concatenated SVG path data (the `d` attribute) for an icon name.
  """
  def icon_path(name) when is_binary(name), do: Map.fetch!(@icon_paths, name)
  def icon_path(name) when is_atom(name), do: icon_path(Atom.to_string(name))

  attr(:id, :string, required: true, doc: "Unique identifier for the morphing icon")
  attr(:from, :string, required: true, doc: "Icon name rendered initially and while inactive")
  attr(:to, :string, required: true, doc: "Icon name morphed into while active")

  attr(:active_state, :string,
    default: "open",
    doc:
      ~s(Value of the watched element's `data-state` that morphs the icon into `to`. The watched element defaults to the closest `[data-part="trigger"]`.)
  )

  attr(:rest, :global)

  @doc """
  Renders an icon that smoothly morphs between two icon shapes when the
  `data-state` of an ancestor trigger changes. The morph is computed entirely on
  the client by the `NooraIconMorph` hook and only animates during the
  transition, so it adds no idle cost.
  """
  def morphing_icon(assigns) do
    assigns =
      assigns
      |> assign(:from_path, icon_path(assigns.from))
      |> assign(:to_path, icon_path(assigns.to))

    ~H"""
    <svg
      id={@id}
      class={"icon icon-tabler icons-tabler-outline icon-tabler-#{String.replace(@from, "_", "-")}"}
      width="24"
      height="24"
      viewBox="0 0 24 24"
      fill="none"
      stroke-linejoin="round"
      stroke-linecap="round"
      xmlns="http://www.w3.org/2000/svg"
      phx-hook="NooraIconMorph"
      phx-update="ignore"
      data-morph-from={@from_path}
      data-morph-to={@to_path}
      data-morph-active={@active_state}
      {@rest}
    >
      <path d={@from_path} fill="currentColor" />
    </svg>
    """
  end
end
