defmodule TuistWeb.Noora.Pages.Introduction do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Noora",
    slug: "introduction",
    description:
      "Tuist's design system for Phoenix LiveView. The components and tokens behind the Tuist dashboard and website."

  alias TuistWeb.Noora.Pages

  def content(assigns) do
    assigns =
      assign(assigns,
        version: noora_version(),
        component_count: length(Pages.components())
      )

    ~H"""
    <section data-part="section">
      <div data-part="cards">
        <.link navigate={Pages.path(Pages.Button)}>
          <.layout_grid />
          <strong>Components</strong>
          <span>{@component_count} Phoenix components, with live examples and their full API.</span>
        </.link>
        <.link navigate={Pages.path(Pages.Colors)}>
          <.chart_donut_4 />
          <strong>Colors</strong>
          <span>The palette and the semantic tokens that switch between light and dark.</span>
        </.link>
        <.link navigate={Pages.path(Pages.Typography)}>
          <.file_text />
          <strong>Typography</strong>
          <span>Type styles for display, headings, body text, and code.</span>
        </.link>
      </div>
    </section>

    <section id="installation" data-part="section">
      <h2><a href="#installation">Installation</a></h2>
      <ol data-part="steps">
        <li>
          <h3>Add the dependency</h3>
          <p>Noora is published to Hex. Add it to the dependencies in <code>mix.exs</code>:</p>
          <.docs_code_window
            id="install-dependency"
            language="Elixir"
            source={"defp deps do\n  [\n    {:noora, \"~> #{@version}\"}\n  ]\nend"}
          />
        </li>
        <li>
          <h3>Import the styles</h3>
          <p>
            Import the fonts and the component styles in <code>assets/css/app.css</code>. To self-host
            Inter Variable and Geist Mono instead, declare their <code>@font-face</code>
            rules and leave out <code>noora/fonts.css</code>.
          </p>
          <.docs_code_window
            id="install-styles"
            language="CSS"
            source={"@import \"noora/fonts.css\";\n@import \"noora/noora.css\";"}
          />
        </li>
        <li>
          <h3>Register the hooks</h3>
          <p>
            Interactive components such as dropdowns, modals, and date pickers run on LiveView hooks. Add them to the socket in <code>assets/js/app.js</code>:
          </p>
          <.docs_code_window
            id="install-hooks"
            language="JavaScript"
            source={"import Noora from \"noora\";\n\nlet liveSocket = new LiveSocket(\"/live\", Socket, {\n  hooks: { ...Noora.Hooks },\n});"}
          />
        </li>
        <li>
          <h3>Use the components</h3>
          <p>
            <code>use Noora</code> imports every component into a LiveView or component module.
          </p>
          <.docs_code_window
            id="install-usage"
            language="Elixir"
            source={"defmodule MyAppWeb.ProjectLive do\n  use MyAppWeb, :live_view\n  use Noora\n\n  def render(assigns) do\n    ~H\"\"\"\n    <.button label=\"Create project\" variant=\"primary\" />\n    \"\"\"\n  end\nend"}
          />
        </li>
      </ol>
    </section>
    """
  end

  defp noora_version do
    [major, minor | _] = :noora |> Application.spec(:vsn) |> to_string() |> String.split(".")
    "#{major}.#{minor}"
  end
end
