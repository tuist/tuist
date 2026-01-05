defmodule TuistCommon.Appsignal.ErrorFilter do
  @moduledoc """
  A Logger filter that prevents specific expected errors from being reported to AppSignal.

  This filter intercepts log messages before they reach AppSignal's Error Backend and
  drops errors that are expected and not actionable, such as client disconnections
  during body reads.

  ## Filtered Errors

  - `Bandit.HTTPError` with message "Body read timeout" - occurs when clients
    interrupt uploads, which is expected behavior and not actionable.
  """

  @doc """
  Logger filter function that drops expected Bandit errors.

  Returns `:stop` to prevent the log message from being processed further,
  or `:ignore` to allow it through.
  """
  @spec filter(:logger.log_event(), term()) :: :stop | :ignore
  def filter(%{meta: %{crash_reason: {%Bandit.HTTPError{message: message}, _stacktrace}}}, _opts)
      when is_binary(message) do
    if String.contains?(message, "Body read timeout") do
      :stop
    else
      :ignore
    end
  end

  def filter(_log_event, _opts), do: :ignore
end
