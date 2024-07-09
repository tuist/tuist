defmodule TuistCloud.Github do
  @moduledoc """
  This module provides utilities to interact with GitHub.
  """
  use Memoize

  @latest_cli_release_url "https://api.github.com/repos/tuist/tuist/releases/latest"

  def latest_cli_release_url do
    @latest_cli_release_url
  end

  def get_most_recent_cli_release() do
    Memoize.Cache.get_or_run(
      :get_most_recent_cli_release,
      fn ->
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
      end,
      expires_in: 60 * 1000
    )
  end
end
