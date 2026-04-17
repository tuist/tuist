defmodule SlackWeb.Router do
  use SlackWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SlackWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :admin do
    plug :basic_auth
  end

  scope "/", SlackWeb do
    pipe_through :browser

    live "/", InvitationRequestLive, :new
    get "/invitations/confirm/:token", InvitationConfirmationController, :confirm
  end

  scope "/admin", SlackWeb.Admin, as: :admin do
    pipe_through [:browser, :admin]

    live "/invitations", InvitationsLive, :index
  end

  if Application.compile_env(:slack, :dev_routes, false) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  defp basic_auth(conn, _opts) do
    config = Application.get_env(:slack, :admin_basic_auth, [])
    username = Keyword.get(config, :username)
    password = Keyword.get(config, :password)

    if is_binary(username) and is_binary(password) and username != "" and password != "" do
      Plug.BasicAuth.basic_auth(conn, username: username, password: password)
    else
      conn
      |> Plug.Conn.send_resp(:service_unavailable, "Admin panel is not configured")
      |> Plug.Conn.halt()
    end
  end
end
