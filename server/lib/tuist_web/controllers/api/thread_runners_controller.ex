defmodule TuistWeb.API.ThreadRunnersController do
  @moduledoc """
  The signed-in person's runners, managed from Tuist Guild: list, register
  (which returns the runner's secret once) and revoke. Only Tuist Guild's
  first-party session can use these, and only while the person has Guild.
  """
  use TuistWeb, :controller

  alias Tuist.FeatureFlags
  alias Tuist.Threads.Runners

  plug TuistWeb.Plugs.AppSessionPlug, apps: ["guild"]
  plug :require_guild

  def index(conn, _params) do
    json(conn, %{runners: conn.assigns.app_user |> Runners.list() |> Enum.map(&Runners.serialize/1)})
  end

  def create(conn, _params) do
    case Runners.register(conn.assigns.app_user, conn.body_params) do
      {:ok, runner, token} ->
        conn |> put_status(:created) |> json(Map.put(Runners.serialize(runner), :token, token))

      {:error, :too_many} ->
        conn |> put_status(:conflict) |> json(%{message: "Remove a runner before adding another."})

      {:error, _} ->
        conn |> put_status(:bad_request) |> json(%{message: "Name the runner and its platform: macos, linux or windows."})
    end
  end

  def delete(conn, %{"id" => id}) do
    case Runners.revoke(conn.assigns.app_user, id) do
      :ok -> send_resp(conn, :no_content, "")
      {:error, _} -> conn |> put_status(:not_found) |> json(%{message: "Not found."})
    end
  end

  defp require_guild(conn, _opts) do
    if FeatureFlags.guild_enabled?(conn.assigns.app_user),
      do: conn,
      else: conn |> put_status(:not_found) |> json(%{message: "Not found."}) |> halt()
  end
end
