defmodule TuistWeb.Marketing.BazelShowcaseController do
  @moduledoc """
  Serves the steps of the build timeline embedded in the Bazel announcement
  post. The dashboard's timeline endpoint reads the trace profile on every
  request and can't be cached; this one serves the showcase invocation from
  the showcase cache, so a spike of visits doesn't become a spike of reads.
  """
  use TuistWeb, :controller

  alias Tuist.Marketing.BazelShowcase
  alias TuistWeb.Errors.NotFoundError

  def timeline(conn, %{"invocation_id" => invocation_id}) when is_binary(invocation_id) do
    case BazelShowcase.timeline_steps(invocation_id) do
      {:ok, steps} ->
        conn
        |> put_resp_header("cache-control", "public, max-age=60")
        |> json(steps)

      {:error, :not_found} ->
        raise NotFoundError, dgettext("errors", "Build not found")
    end
  end

  def timeline(_conn, _params), do: raise(NotFoundError, dgettext("errors", "Build not found"))
end
