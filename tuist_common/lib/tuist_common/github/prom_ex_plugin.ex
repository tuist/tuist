defmodule TuistCommon.GitHub.PromExPlugin do
  @moduledoc """
  Exposes the GitHub REST API rate-limit budget reported on API responses.

  The gauges are re-emitted from `TuistCommon.GitHub.RateLimit` on a poll
  rather than straight from the response, so a scrape that follows no GitHub
  call still carries the last known budget.
  """
  use PromEx.Plugin

  alias TuistCommon.GitHub.RateLimit

  @poll_event [:tuist_common, :github, :rate_limit, :poll]

  @doc false
  def poll_event_name, do: @poll_event

  @impl true
  def polling_metrics(opts) do
    poll_rate = Keyword.get(opts, :poll_rate, to_timeout(second: 15))
    server = Keyword.get(opts, :rate_limit_server, RateLimit)

    [
      Polling.build(
        :tuist_github_rate_limit_polling_metrics,
        poll_rate,
        {__MODULE__, :execute_rate_limit_telemetry, [server]},
        [
          last_value(
            [:tuist, :github, :rate_limit, :limit],
            event_name: @poll_event,
            measurement: :limit,
            tags: [:resource],
            description: "The `x-ratelimit-limit` value on the most recent GitHub API response."
          ),
          last_value(
            [:tuist, :github, :rate_limit, :used],
            event_name: @poll_event,
            measurement: :used,
            tags: [:resource],
            description: "The `x-ratelimit-used` value on the most recent GitHub API response."
          ),
          last_value(
            [:tuist, :github, :rate_limit, :reset, :timestamp, :seconds],
            event_name: @poll_event,
            measurement: :reset,
            tags: [:resource],
            description:
              "The `x-ratelimit-reset` value, as a Unix timestamp, on the most recent GitHub API response."
          )
        ]
      )
    ]
  end

  @doc false
  def execute_rate_limit_telemetry(server \\ RateLimit) do
    Enum.each(RateLimit.snapshot(server), fn {resource, measurements} ->
      :telemetry.execute(@poll_event, measurements, %{resource: resource})
    end)
  end
end
