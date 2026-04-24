defmodule TuistWeb.Utilities.HtmlToMarkdownTest do
  use ExUnit.Case, async: true

  alias TuistWeb.Utilities.HtmlToMarkdown

  test "converts HTML to markdown while preferring the main content" do
    html = """
    <html>
      <head>
        <title>Example Page</title>
      </head>
      <body>
        <nav>
          <a href="/pricing">Pricing</a>
        </nav>
        <main>
          <h1>Example Page</h1>
          <p>A <a href="/docs">documentation link</a>.</p>
          <pre><code class="language-elixir">IO.puts("hi")
    </code></pre>
        </main>
      </body>
    </html>
    """

    markdown = HtmlToMarkdown.convert(html, request_url: "https://tuist.dev/about")

    assert markdown =~ "# Example Page"
    assert markdown =~ "[documentation link](https://tuist.dev/docs)."
    assert markdown =~ "```elixir\nIO.puts(\"hi\")\n```"
    refute markdown =~ "Pricing"
    refute markdown =~ "<main>"
  end
end
