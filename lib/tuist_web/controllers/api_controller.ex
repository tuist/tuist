defmodule TuistWeb.APIController do
  use TuistWeb, :controller

  import Plug.Conn

  def docs(conn, _params) do
    bearer_token =
      if user = conn.assigns[:current_user] do
        {:ok, access_token, _opts} =
          Tuist.Authentication.encode_and_sign(user, %{},
            token_type: :access,
            ttl: {10, :minutes}
          )

        access_token
      end

    conn
    |> assign(:bearer_token, bearer_token)
    |> assign(:head_title, "API Documentation · Tuist")
    |> put_root_layout(false)
    |> render(:docs, layout: false)
  end
end
