defmodule TuistWeb.TimezoneHook do
  @moduledoc """
  LiveView hook to automatically assign user timezone to socket.
  """

  import Phoenix.Component, only: [assign: 3]
  alias Tuist.Utilities.DateFormatter

  def on_mount(:assign_timezone, _params, session, socket) do
    user_timezone = DateFormatter.get_user_timezone(session, socket)
    
    {:cont, assign(socket, :user_timezone, user_timezone)}
  end
end