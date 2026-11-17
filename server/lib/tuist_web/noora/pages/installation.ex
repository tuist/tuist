defmodule TuistWeb.Noora.Pages.Installation do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Installation",
    description: "Add Noora to a Phoenix application: the dependency, the styles, the hooks, and the components."

  def content(assigns) do
    assigns = assign(assigns, version: noora_version())

    ~H"""
    <section data-part="section">
      <ol data-part="steps">
        <li id="dependency">
          <h2><a href="#dependency">Add the dependency</a></h2>
          <p>Noora is published to Hex. Add it to the dependencies in <code>mix.exs</code>:</p>
          <.docs_code_window
            id="install-dependency"
            language="Elixir"
            source={"defp deps do\n  [\n    {:noora, \"~> #{@version}\"}\n  ]\nend"}
          />
        </li>
        <li id="styles">
          <h2><a href="#styles">Import the styles</a></h2>
          <p>
            Import the fonts and the component styles in <code>assets/css/app.css</code>.
            <code>noora/fonts.css</code>
            loads Inter Variable and Geist Mono from Google Fonts and rsms.me.
          </p>
          <.docs_code_window
            id="install-styles"
            language="CSS"
            source={"@import \"noora/fonts.css\";\n@import \"noora/noora.css\";"}
          />
        </li>
        <li id="hooks">
          <h2><a href="#hooks">Register the hooks</a></h2>
          <p>
            Interactive components such as dropdowns, modals, and date pickers run on LiveView hooks. Add them to the socket in <code>assets/js/app.js</code>:
          </p>
          <.docs_code_window
            id="install-hooks"
            language="JavaScript"
            source={"import Noora from \"noora\";\n\nlet liveSocket = new LiveSocket(\"/live\", Socket, {\n  hooks: { ...Noora.Hooks },\n});"}
          />
        </li>
        <li id="usage">
          <h2><a href="#usage">Use the components</a></h2>
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

    <section id="self-hosted-fonts" data-part="section">
      <h2><a href="#self-hosted-fonts">Self-hosted fonts</a></h2>
      <p>
        To avoid requests to third-party font hosts, serve Inter Variable and Geist Mono yourself. Declare their font faces and import
        <code>noora/noora.css</code>
        without <code>noora/fonts.css</code>.
      </p>
      <.docs_code_window
        id="install-self-hosted-fonts"
        language="CSS"
        source={"@font-face {\n  font-family: \"Inter Variable\";\n  src: url(\"/fonts/InterVariable.woff2\") format(\"woff2\");\n  font-weight: 100 900;\n  font-display: swap;\n  font-optical-sizing: auto;\n}\n\n@font-face {\n  font-family: \"Geist Mono\";\n  src: url(\"/fonts/GeistMono.woff2\") format(\"woff2\");\n  font-weight: 400 700;\n  font-display: swap;\n}\n\n@import \"noora/noora.css\";"}
      />
    </section>
    """
  end

  defp noora_version do
    [major, minor | _] = :noora |> Application.spec(:vsn) |> to_string() |> String.split(".")
    "#{major}.#{minor}"
  end
end
