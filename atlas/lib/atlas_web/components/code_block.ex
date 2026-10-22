defmodule AtlasWeb.CodeBlock do
  @moduledoc "Read-only, HTML-escaped source highlighting with light and dark themes."

  use Phoenix.Component

  import Phoenix.HTML, only: [raw: 1]

  @max_highlight_bytes 262_144

  attr :source, :string, required: true
  attr :language, :string, default: "json", values: ~w(json javascript)
  attr :rest, :global

  def code_block(assigns) do
    assigns = assign(assigns, :highlighted, highlight(assigns.source, assigns.language))

    ~H"""
    <div data-part="code-block" data-language={@language} {@rest}>
      <%= if @highlighted do %>
        {raw(@highlighted)}
      <% else %>
        <pre><code>{@source}</code></pre>
      <% end %>
    </div>
    """
  end

  defp highlight(source, language) when byte_size(source) <= @max_highlight_bytes do
    case Lumis.highlight(source,
           formatter:
             {:html_multi_themes,
              language: language, themes: [light: "github_light", dark: "github_dark"], default_theme: "light-dark()"}
         ) do
      {:ok, html} -> html
      {:error, _} -> nil
    end
  end

  defp highlight(_, _), do: nil
end
