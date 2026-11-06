defmodule Tuist.BuildEntities.QueryLimitError do
  @moduledoc """
  Raised when a build entity read exceeds its ClickHouse execution time
  (`TIMEOUT_EXCEEDED`, code 159) or memory (`MEMORY_LIMIT_EXCEEDED`, code 241)
  limit. Surfaces translate it into a retryable response; any other database
  error is left as it was.
  """
  defexception [:code, message: "The build entity query exceeded its time or memory limit."]
end
