defmodule AtlasWeb.SupportChatVerificationController do
  use AtlasWeb, :controller

  alias Atlas.Support

  def confirm(conn, %{"token" => token}) do
    case Support.confirm_chat_email(token) do
      {:ok, _thread} ->
        html_message(conn, "Email confirmed", "Your email is confirmed. You can return to your support chat.")

      {:error, _reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> html_message("The link is not valid", "This confirmation link is invalid or has expired.")
    end
  end

  defp html_message(conn, title, body) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(
      conn.status || 200,
      """
      <!doctype html>
      <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width,initial-scale=1">
          <title>#{title}</title>
        </head>
        <body style="margin:0;background:#f6f6f4;color:#252523;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;">
          <main style="max-width:560px;margin:10vh auto;padding:24px;">
            <h1 style="margin:0 0 12px;font-size:28px;">#{title}</h1>
            <p style="margin:0;font-size:16px;line-height:1.5;">#{body}</p>
          </main>
        </body>
      </html>
      """
    )
  end
end
