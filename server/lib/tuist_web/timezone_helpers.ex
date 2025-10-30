defmodule TuistWeb.TimezoneHelpers do
  @moduledoc """
  Helper functions for extracting user timezone in LiveViews.
  """

  @doc """
  Extracts user timezone from session (set by TimezonePlug) or LiveView connection params (fallback for first-time users).
  """
  def get_user_timezone(session, socket) do
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