defmodule TuistWeb.Oauth.AndroidCallbackController do
  use TuistWeb, :controller

  def callback(conn, params) do
    allowed_params = Map.take(params, ["code", "state", "error", "error_description"])
    query_string = URI.encode_query(allowed_params)
    custom_scheme_url = "tuist://oauth-callback?#{query_string}"
    intent_url = "intent://oauth-callback?#{query_string}#Intent;scheme=tuist;package=dev.tuist.app;end"

    escaped_custom_scheme_url = html_escape(custom_scheme_url)
    escaped_intent_url = html_escape(intent_url)

    html = """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Tuist</title>
      <style>
        body {
          font-family: -apple-system, system-ui, sans-serif;
          display: flex;
          align-items: center;
          justify-content: center;
          min-height: 100vh;
          margin: 0;
          background: #f5f5f5;
        }
        .card {
          text-align: center;
          background: white;
          border-radius: 16px;
          padding: 40px 32px;
          box-shadow: 0 2px 8px rgba(0,0,0,0.1);
          max-width: 320px;
        }
        h1 { font-size: 20px; margin: 0 0 8px; }
        p { color: #666; font-size: 14px; margin: 0 0 24px; }
        a {
          display: inline-block;
          background: #6C3FE0;
          color: white;
          text-decoration: none;
          padding: 12px 32px;
          border-radius: 8px;
          font-size: 16px;
          font-weight: 500;
        }
      </style>
      <script>window.location.href = "#{escaped_custom_scheme_url}";</script>
    </head>
    <body>
      <div class="card">
        <h1>Authentication complete</h1>
        <p>Tap the button below to return to the app.</p>
        <a href="#{escaped_intent_url}">Open Tuist</a>
      </div>
    </body>
    </html>
    """

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

  defp html_escape(string) do
    string
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end
end
