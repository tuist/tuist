defmodule AtlasWeb.PlatformIcon do
  @moduledoc """
  Renders the brand logo for a Sentry Software Development Kit
  `platform` identifier — Elixir's droplet, JavaScript's yellow badge,
  and so on. Icons come from Simple Icons (MIT-licensed) shipped under
  `priv/static/images/platforms/`.

  Unknown platforms fall back to a neutral letter badge so any
  identifier a Software Development Kit sends renders as something.
  """

  use Phoenix.Component

  attr :platform, :string,
    default: nil,
    doc: "SDK platform identifier such as 'elixir' or 'javascript'."

  attr :size, :string, default: "medium", values: ~w(small medium)

  attr :label, :boolean,
    default: false,
    doc: "Whether to render the friendly language name next to the badge."

  attr :rest, :global

  def platform_icon(assigns) do
    key = normalize(assigns.platform)
    {icon_file, friendly_name} = resolve(key)

    assigns =
      assigns
      |> assign(:icon_file, icon_file)
      |> assign(:friendly_name, friendly_name)
      |> assign(:letter, letter(key))

    ~H"""
    <span class="platform-icon" data-size={@size} title={@friendly_name} {@rest}>
      <span :if={@icon_file} data-part="logo" aria-hidden="true">
        <img src={"/images/platforms/#{@icon_file}"} alt={@friendly_name} />
      </span>
      <span
        :if={!@icon_file}
        data-part="badge"
        aria-hidden="true"
      >
        {@letter}
      </span>
      <span :if={@label} data-part="label">{@friendly_name}</span>
    </span>
    """
  end

  defp normalize(nil), do: nil
  defp normalize(""), do: nil
  defp normalize(name) when is_binary(name), do: String.downcase(name)
  defp normalize(name), do: name |> to_string() |> String.downcase()

  # {icon_file | nil, friendly label}
  defp resolve("elixir"), do: {"elixir.svg", "Elixir"}
  defp resolve("erlang"), do: {"erlang.svg", "Erlang"}
  defp resolve("javascript"), do: {"javascript.svg", "JavaScript"}
  defp resolve("node"), do: {"nodedotjs.svg", "Node.js"}
  defp resolve("node.js"), do: {"nodedotjs.svg", "Node.js"}
  defp resolve("typescript"), do: {"typescript.svg", "TypeScript"}
  defp resolve("python"), do: {"python.svg", "Python"}
  defp resolve("ruby"), do: {"ruby.svg", "Ruby"}
  defp resolve("go"), do: {"go.svg", "Go"}
  defp resolve("java"), do: {"java.svg", "Java"}
  defp resolve("csharp"), do: {"dotnet.svg", "C#"}
  defp resolve("dotnet"), do: {"dotnet.svg", ".NET"}
  defp resolve("php"), do: {"php.svg", "PHP"}
  defp resolve("perl"), do: {"perl.svg", "Perl"}
  defp resolve("rust"), do: {"rust.svg", "Rust"}
  defp resolve("swift"), do: {"swift.svg", "Swift"}
  defp resolve("cocoa"), do: {"apple.svg", "Cocoa"}
  defp resolve("objc"), do: {"apple.svg", "Objective-C"}
  defp resolve("kotlin"), do: {"kotlin.svg", "Kotlin"}
  defp resolve("dart"), do: {"dart.svg", "Dart"}
  defp resolve("flutter"), do: {"flutter.svg", "Flutter"}
  defp resolve("android"), do: {"android.svg", "Android"}
  defp resolve("c"), do: {"c.svg", "C"}
  defp resolve("cpp"), do: {"cplusplus.svg", "C++"}
  defp resolve("cplusplus"), do: {"cplusplus.svg", "C++"}
  defp resolve("scala"), do: {"scala.svg", "Scala"}
  defp resolve("haskell"), do: {"haskell.svg", "Haskell"}
  defp resolve("clojure"), do: {"clojure.svg", "Clojure"}
  defp resolve("native"), do: {nil, "Native"}
  defp resolve("other"), do: {nil, "Other"}
  defp resolve(nil), do: {nil, "Unknown"}
  defp resolve(name) when is_binary(name), do: {nil, String.capitalize(name)}
  defp resolve(name), do: {nil, to_string(name)}

  defp letter(nil), do: "?"
  defp letter(name) when is_binary(name), do: name |> String.slice(0, 2) |> String.upcase()
  defp letter(_), do: "?"
end
