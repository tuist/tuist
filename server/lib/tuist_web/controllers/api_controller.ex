defmodule TuistWeb.APIController do
  use TuistWeb, :controller

  import Plug.Conn

  def docs(conn, _params) do
    head_image =
      if Tuist.Environment.tuist_hosted?() do
        Tuist.Environment.app_url(path: "/images/open-graph/api-docs-card.jpeg")
      end

    # The token acts for the user in every account, so a session that skipped
    # an organization's enforced single sign-on does not get one.
    user = conn.assigns[:current_user]

    bearer_token =
      if user && Tuist.Accounts.sso_requirement(user, conn.assigns[:current_user_session]) == :ok do
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
