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

  ## Animated transitions

  `<.icon>` can animate between two icons when the `data-state` of an ancestor
  changes (e.g. a dropdown trigger opening). Pass `active_name` and a
  `transition` strategy:

  ```elixir
  <.icon id="switcher" name="selector" active_name="selector_2" transition="morph"
    watch="[data-part='trigger']" active_state="open" />
  ```

  Strategies:
  - `"morph"` — tween one filled path into the other. Raises at render time if
    either icon is not a filled path (see `morphable?/1`).
  - `"crossfade_rotate"` — crossfade and rotate the two icons. Works for any pair.
  - `"auto"` (default) — morph when both icons are compatible, otherwise crossfade.

  ## Adding an icon

  Icons are automatically read and generated from the `icons` folder. To add an icon, simply add a SVG file to the folder. File names are
  required to be alphanumeric. Hyphens in the file name are automatically substituted to underscores.
  """
  use Phoenix.Component

  @icons_path Path.join(File.cwd!(), "lib/noora/icons")
  @external_resource @icons_path

  # Noora icons must be filled paths (`fill="currentColor"`) so they render and
  # animate (morph) correctly. Stroked icons would render as solid blobs, so we
  # fail the build if any are added.
  @stroked_icons for file <- File.ls!(@icons_path),
                     Path.extname(file) == ".svg",
                     content = File.read!(Path.join(@icons_path, file)),
                     String.contains?(content, ~s(stroke="currentColor")),
                     do: Path.basename(file, ".svg")

  if @stroked_icons != [] do
    raise ~s|Noora icons must be filled paths (fill="currentColor"), but these are stroked: | <>
            Enum.join(@stroked_icons, ", ") <>
            ". Convert them to filled paths so they render and animate correctly."
  end

  # Icons whose path is filled with `currentColor` — the set that is safe to
  # morph. Everything else falls back to a crossfade transition.
  @morphable_icons (for file <- File.ls!(@icons_path),
                        Path.extname(file) == ".svg",
                        content = File.read!(Path.join(@icons_path, file)),
                        String.contains?(content, ~s(fill="currentColor")),
                        into: MapSet.new() do
                      file |> Path.basename(".svg") |> String.replace("-", "_")
                    end)

  def icon(%{active_name: active_name} = assigns) when is_binary(active_name) do
    assigns =
      assigns
      |> assign_new(:id, fn -> nil end)
      |> assign_new(:transition, fn -> "auto" end)
      |> assign_new(:watch, fn -> nil end)
      |> assign_new(:active_state, fn -> "open" end)

    case resolve_transition(assigns.transition, assigns.name, active_name) do
      :morph -> render_morph_icon(assigns)
      :crossfade_rotate -> render_crossfade_icon(assigns)
    end
  end

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

  @doc """
  Whether an icon can be morphed (it is a filled-path icon). Stroked or
  non-`currentColor` icons fall back to a crossfade transition.
  """
  def morphable?(name) when is_binary(name), do: MapSet.member?(@morphable_icons, name)
  def morphable?(name) when is_atom(name), do: morphable?(Atom.to_string(name))

  # Resolves the requested transition strategy. `"morph"` requires compatible
  # (filled-path) icons and raises otherwise so misuse fails loudly rather than
  # rendering an incorrect shape. `"auto"` morphs when possible and crossfades
  # otherwise.
  defp resolve_transition("crossfade_rotate", _from, _to), do: :crossfade_rotate

  defp resolve_transition("auto", from, to) do
    if morphable?(from) and morphable?(to), do: :morph, else: :crossfade_rotate
  end

  defp resolve_transition("morph", from, to) do
    incompatible = Enum.reject([from, to], &morphable?/1)

    if incompatible == [] do
      :morph
    else
      raise ArgumentError,
            ~s(Noora.Icon: transition="morph" only supports filled-path icons, but ) <>
              Enum.map_join(incompatible, ", ", &inspect/1) <>
              ~s( cannot be morphed. Use transition="crossfade_rotate" or transition="auto".)
    end
  end

  defp icon_class(name), do: "icon icon-tabler icons-tabler-outline icon-tabler-#{String.replace(name, "_", "-")}"

  defp render_morph_icon(assigns) do
    assigns =
      assigns
      |> assign(:from_path, icon_path(assigns.name))
      |> assign(:to_path, icon_path(assigns.active_name))

    ~H"""
    <svg
      id={@id}
      class={icon_class(@name)}
      width="24"
      height="24"
      viewBox="0 0 24 24"
      fill="none"
      stroke-linejoin="round"
      stroke-linecap="round"
      xmlns="http://www.w3.org/2000/svg"
      phx-hook="NooraIconTransition"
      phx-update="ignore"
      data-transition="morph"
      data-watch={@watch}
      data-active-state={@active_state}
      data-morph-from={@from_path}
      data-morph-to={@to_path}
    >
      <path d={@from_path} fill="currentColor" />
    </svg>
    """
  end

  defp render_crossfade_icon(assigns) do
    ~H"""
    <span
      id={@id}
      class="noora-icon-transition"
      phx-hook="NooraIconTransition"
      phx-update="ignore"
      data-transition="crossfade_rotate"
      data-watch={@watch}
      data-active-state={@active_state}
    >
      <span data-part="icon-from"><.icon name={@name} /></span>
      <span data-part="icon-to"><.icon name={@active_name} /></span>
    </span>
    """
  end
end
