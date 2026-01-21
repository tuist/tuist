defmodule TuistCommon.Appsignal.ErrorFilter do
  @moduledoc """
  A Logger filter that prevents specific expected errors from being reported to AppSignal.

  This filter intercepts log messages before they reach AppSignal's Error Backend and
  drops errors that are expected and not actionable.

  ## Note on Body Read Errors

  With the modified Bandit (which checks if the peer is still connected on timeout),
  client disconnects during body reads now raise `Bandit.TransportError` instead of
  `Bandit.HTTPError`. The `TransportError` is already ignored via AppSignal's
  `ignore_errors` configuration, so no additional filtering is needed here.

  `Bandit.HTTPError` with "Body read timeout" now indicates a genuine timeout
  (not a client disconnect) and should be reported for investigation.
  """

  @doc """
  Logger filter function that drops expected errors.

  Returns `:stop` to prevent the log message from being processed further,
  or `:ignore` to allow it through.
  """
  def filter(_log_event, _opts), do: :ignore
end
