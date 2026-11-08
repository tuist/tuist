defmodule TuistLabelsWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :tuist_labels

  @session [store: :cookie, key: "_tuist_labels", signing_salt: "labels-cookie", same_site: "Lax"]
  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session]],
    longpoll: false

  plug TuistLabelsWeb.Security
  plug Plug.Static, at: "/", from: :tuist_labels, only: ~w(assets sdk)

  plug Plug.Parsers,
    parsers: [:urlencoded, :json],
    pass: [],
    json_decoder: Jason,
    length: 12 * 1024 * 1024

  plug Plug.Session, @session
  plug TuistLabelsWeb.Router
end

defmodule TuistLabelsWeb.Errors do
  def render(<<_status::binary-size(3), ".html">> = template, _),
    do: Phoenix.Controller.status_message_from_template(template)

  def render(template, _), do: %{error: Phoenix.Controller.status_message_from_template(template)}
end
