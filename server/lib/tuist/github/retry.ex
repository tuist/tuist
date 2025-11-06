defmodule Tuist.GitHub.Retry do
  @moduledoc """
  Shared retry logic for GitHub API requests.
  Handles transient errors with exponential backoff.
  """

  @doc """
  Determines whether a GitHub API request should be retried based on the response or exception.

  ## Parameters
    - request: The Req request struct (unused but required by Req retry interface)
    - response_or_exception: The response or exception from the request

  ## Returns
    - true if the request should be retried
    - false otherwise

  ## Retryable conditions:
    - Server errors: 408, 429, 500, 502, 503, 504
    - Transport errors: timeout, econnrefused, closed
    - HTTP/2 errors: unprocessed, closed_for_writing, refused_stream
  """
  def should_retry?(_request, response_or_exception) do
    case response_or_exception do
      # Retry on server errors
      %Req.Response{status: status} when status in [408, 429, 500, 502, 503, 504] ->
        true

      # Retry on transport errors
      %Req.TransportError{reason: reason} when reason in [:timeout, :econnrefused, :closed] ->
        true

      # Retry on HTTP/2 connection errors
      %Req.HTTPError{protocol: :http2, reason: reason}
      when reason in [
             :unprocessed,
             :closed_for_writing,
             {:server_closed_request, :refused_stream}
           ] ->
        true

      _ ->
        false
    end
  end

  @doc """
  Calculates exponential backoff delay for retries.

  ## Parameters
    - retry_count: The current retry attempt (0-indexed)

  ## Returns
    - Delay in milliseconds

  ## Example delays:
    - Attempt 1: 1000ms (1s)
    - Attempt 2: 2000ms (2s)
    - Attempt 3: 4000ms (4s)
  """
  def exponential_backoff(retry_count) do
    trunc(:math.pow(2, retry_count) * 1000)
  end

  @doc """
  Returns the standard retry options for GitHub API requests.

  ## Returns
    - Keyword list with retry, max_retries, and retry_delay options
  """
  def retry_options do
    [
      retry: &should_retry?/2,
      max_retries: 3,
      retry_delay: &exponential_backoff/1
    ]
  end
end
