defmodule AtlasWeb.GTMSubscriptionController do
  use AtlasWeb, :controller

  alias Atlas.GTM.Subscriptions
  alias AtlasWeb.ClientIP
  alias AtlasWeb.SubscriptionRateLimit

  def create(conn, params) do
    attrs = Map.take(params, ["email", "first_name", "last_name", "user_group", "source", "metadata"])
    attrs = Map.put_new(attrs, "source", "email-digest")

    case SubscriptionRateLimit.check(ClientIP.get(conn), params["email"]) do
      :ok -> queue_subscription(conn, attrs)
      {:error, retry_after} -> too_many_requests(conn, retry_after)
    end
  end

  defp queue_subscription(conn, attrs) do
    case Subscriptions.request_digest_subscription(attrs) do
      {:ok, _subscriber} ->
        conn
        |> put_status(:accepted)
        |> json(%{ok: true, status: "confirmation_queued"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, errors: changeset_errors(changeset)})

      {:error, _reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{ok: false, error: "subscription unavailable"})
    end
  end

  defp too_many_requests(conn, retry_after) do
    conn
    |> put_resp_header("retry-after", Integer.to_string(retry_after))
    |> put_status(:too_many_requests)
    |> json(%{ok: false, error: "too many requests"})
  end

  def confirm(conn, %{"token" => token}) do
    case Subscriptions.confirm(token) do
      {:ok, %{audience: audience}} ->
        html_message(conn, "Subscription confirmed", "You are now subscribed to #{audience.name}.")

      {:error, _reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> html_message("The link is not valid", "This confirmation link is invalid or has expired.")
    end
  end

  def unsubscribe(conn, %{"token" => token}) do
    case Subscriptions.unsubscribe(token) do
      {:ok, %{audience: audience}} ->
        html_message(conn, "Unsubscribed", "You will no longer receive #{audience.name}.")

      {:error, _reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> html_message("The link is not valid", "This unsubscribe link is invalid or has expired.")
    end
  end

  def unsubscribe_one_click(conn, %{"token" => token}) do
    case Subscriptions.unsubscribe(token) do
      {:ok, _subscription} -> json(conn, %{ok: true, status: "unsubscribed"})
      {:error, _reason} -> conn |> put_status(:unprocessable_entity) |> json(%{ok: false})
    end
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, options} ->
      Enum.reduce(options, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp html_message(conn, title, body) do
    title = title |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
    body = body |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

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
            <section style="background:white;border:1px solid #e6e6e2;border-radius:12px;padding:32px;">
              <h1 style="margin-top:0;">#{title}</h1>
              <p>#{body}</p>
            </section>
          </main>
        </body>
      </html>
      """
    )
  end
end
