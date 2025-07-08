defmodule Tuist.ErrorTracker.Ignorer do
  @moduledoc ~S"""
  This module contains the logic that the :error_tracker dependency uses to determine whether an error should be ignored or not.
  """
  @behaviour ErrorTracker.Ignorer

  @impl true
  def ignore?(%ErrorTracker.Error{} = error, _context) do
    error.kind in [
      "Elixir.TuistWeb.Errors.UnauthorizedError",
      "Elixir.TuistWeb.Errors.NotFoundError",
      "Elixir.TuistWeb.Errors.TooManyRequestsError"
    ]
  end
end
