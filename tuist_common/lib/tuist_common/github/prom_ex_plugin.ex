defmodule TuistCommon.GitHub.PromExPlugin do
  @moduledoc """
  Exposes the GitHub REST API rate-limit budget reported on API responses.
  """
  use PromEx.Plugin

  alias TuistCommon.GitHub

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(
        :tuist_github_rate_limit_event_metrics,
        [
          last_value(
            [:tuist, :github, :rate_limit, :limit],
            event_name: GitHub.rate_limit_event_name(),
            measurement: :limit,
            tags: [:resource],
            description: "The `x-ratelimit-limit` value on the most recent GitHub API response."
          ),
          last_value(
            [:tuist, :github, :rate_limit, :used],
            event_name: GitHub.rate_limit_event_name(),
            measurement: :used,
            tags: [:resource],
            description: "The `x-ratelimit-used` value on the most recent GitHub API response."
          )
        ]
      )
    ]
  end
end
