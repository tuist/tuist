defmodule TuistWeb.API.ThreadRunnerConnectionController do
  @moduledoc """
  What a runner daemon (`tuist-guild-runner`) calls with its own secret, never
  a person's session: `poll` reports it online with what it allows and waits
  for operations; `respond` answers one it claimed. Request and response
  bodies hold files and command output, so the routes don't log params.
  """
  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.FeatureFlags
  alias Tuist.Threads.Runners

  @max_wait_ms 25_000

  plug :authenticate

  def poll(conn, params) do
    wait =
      case Integer.parse(to_string(params["wait_ms"] || "")) do
        {value, ""} -> value |> max(0) |> min(@max_wait_ms)
        _ -> @max_wait_ms
      end

    requests = Runners.poll(conn.assigns.runner, conn.body_params, wait)
    json(conn, %{requests: requests})
  end

  def respond(conn, %{"id" => id}) do
    case Runners.respond(conn.assigns.runner, id, conn.body_params) do
      :ok -> send_resp(conn, :no_content, "")
      # The caller gave up, or another poll already answered it.
      {:error, _} -> conn |> put_status(:gone) |> json(%{message: "The request is no longer waiting."})
    end
  end

  defp authenticate(conn, _opts) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, runner} <- Runners.authenticate(token),
         %{} = user <- Accounts.get_user_by_id(runner.user_id),
         true <- user.active and is_nil(user.disabled_at) and FeatureFlags.guild_enabled?(user) do
      assign(conn, :runner, runner)
    else
      _ -> conn |> put_status(:unauthorized) |> json(%{message: "Register this runner again from Tuist Guild."}) |> halt()
    end
  end
end
