defmodule TuistWeb.SlackOAuthHTML do
  use TuistWeb, :html

  def render("popup_close.html", assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Slack Connected</title>
        <style>
          body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            display: flex;
            align-items: center;
            justify-content: center;
            height: 100vh;
            margin: 0;
            background: #f5f5f5;
          }
          .message {
            text-align: center;
            color: #333;
          }
        </style>
      </head>
      <body>
        <div class="message">
          <p>Channel connected successfully. This window will close automatically.</p>
        </div>
        <div id="channel-data" data-channel-token={@channel_token} style="display: none;"></div>
        <script nonce={get_csp_nonce()}>
          const dataEl = document.getElementById("channel-data");
          const channelToken = dataEl.dataset.channelToken || null;
          const nonce = sessionStorage.getItem("slack_popup_nonce");
          sessionStorage.removeItem("slack_popup_nonce");
          const channel = new BroadcastChannel("oauth_popup");
          channel.postMessage({
            type: "oauth_complete",
            success: true,
            channel_token: channelToken,
            nonce: nonce
          });
          channel.close();
          window.close();
        </script>
      </body>
    </html>
    """
  end
end
