defmodule Tuist.Github do
  @moduledoc """
  This module provides utilities to interact with GitHub.
  """
  use Nebulex.Caching.Decorators

  @latest_cli_release_url "https://api.github.com/repos/tuist/tuist/releases/latest"

  def latest_cli_release_url do
    @latest_cli_release_url
  end

  @decorate cacheable(cache: {Tuist.Cache, :tuist, []}, opts: [ttl: :timer.hours(1)])
  def get_most_recent_cli_release() do
    case Req.get(latest_cli_release_url()) do
      {:ok, %Req.Response{status: 200, body: release}} ->
        %{
          name: release["name"],
          published_at: Timex.parse!(release["published_at"], "{ISO:Extended}"),
          html_url: release["html_url"]
        }

      {:error, _reason} ->
        nil
    end
  end
end
