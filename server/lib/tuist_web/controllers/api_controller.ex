defmodule TuistWeb.APIController do
  use TuistWeb, :controller

  import Plug.Conn

  alias TuistWeb.Helpers.OpenGraph

  def docs(conn, _params) do
    head_image =
      if Tuist.Environment.tuist_hosted?() do
        Tuist.Environment.app_url(path: OpenGraph.image_path(:marketing_api_docs, title: "API Docs"))
      end

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
    |> assign(:head_image, head_image)
    |> put_root_layout(false)
    |> render(:docs, layout: false)
  end
end
