defmodule TuistWeb.Timezone do
  @moduledoc """
  LiveView hook to automatically assign user timezone to socket.
  """

  import Phoenix.Component, only: [assign: 3]

  def on_mount(:assign_timezone, _params, session, socket) do
    user_timezone = get_user_timezone(session, socket)

    {:cont, assign(socket, :user_timezone, user_timezone)}
  end

  # Extracts user timezone from session (set by TimezonePlug) or LiveView connection params (fallback for first-time users).
  defp get_user_timezone(session, socket) do
    case Map.get(session, "user_timezone") do
      nil ->
        case Phoenix.LiveView.get_connect_params(socket) do
          %{"user_timezone" => timezone} -> timezone
          _ -> nil
        end

      timezone ->
        timezone
    end
  end
end
