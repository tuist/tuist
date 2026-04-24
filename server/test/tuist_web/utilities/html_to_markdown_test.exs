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

    assert markdown ==
             String.trim_trailing("""
             # Example Page

             A [documentation link](https://tuist.dev/docs).

             ```elixir
             IO.puts("hi")

             ```
             """)
  end

  test "uses the document title when the content does not start with a heading" do
    html = """
    <html>
      <head>
        <title>Pricing</title>
      </head>
      <body>
        <main>
          <p>Simple pricing overview.</p>
        </main>
      </body>
    </html>
    """

    markdown = HtmlToMarkdown.convert(html)

    assert markdown ==
             String.trim_trailing("""
             # Pricing

             Simple pricing overview.
             """)
  end
end
