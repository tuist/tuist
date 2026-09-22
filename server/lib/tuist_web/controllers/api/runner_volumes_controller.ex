defmodule TuistWeb.API.RunnerVolumesController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias Tuist.FeatureFlags
  alias Tuist.Runners.CacheVolumes.Query
  alias TuistWeb.API.Authorization.AuthorizationPlug
  alias TuistWeb.API.Responses
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.RunnerVolumes

  plug TuistWeb.Plugs.LoaderPlug
  plug TuistWeb.Plugs.CastAndValidate, json_render_error_v2: true, render_error: TuistWeb.RenderAPIErrorPlug
  plug AuthorizationPlug, {:account, :runners} when action != :clear
  plug AuthorizationPlug, {:account, :account, :update} when action == :clear

  tags ["Runners"]

  operation(:list,
    summary: "List runner volumes filtered by name and repository.",
    operation_id: "listRunnerVolumes",
    parameters: RunnerVolumes.parameters(:list),
    responses: %{
      ok: {"Runner volume data", "application/json", RunnerVolumes.response(:list)},
      bad_request: {"Invalid parameters", "application/json", Error},
      forbidden: {"Forbidden", "application/json", Error},
      not_found: {"Volume or job not found, or runners disabled", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  operation(:show,
    summary: "Get runner volume details.",
    operation_id: "getRunnerVolume",
    parameters: RunnerVolumes.parameters(:show),
    responses: %{
      ok: {"Runner volume data", "application/json", RunnerVolumes.response(:show)},
      bad_request: {"Invalid parameters", "application/json", Error},
      forbidden: {"Forbidden", "application/json", Error},
      not_found: {"Volume or job not found, or runners disabled", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  operation(:jobs,
    summary: "List the jobs that used a runner volume.",
    operation_id: "listRunnerVolumeJobs",
    parameters: RunnerVolumes.parameters(:jobs),
    responses: %{
      ok: {"Runner volume data", "application/json", RunnerVolumes.response(:jobs)},
      bad_request: {"Invalid parameters", "application/json", Error},
      forbidden: {"Forbidden", "application/json", Error},
      not_found: {"Volume or job not found, or runners disabled", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  operation(:job_volumes,
    summary: "List the volumes mounted by a runner job.",
    operation_id: "listRunnerJobVolumes",
    parameters: RunnerVolumes.parameters(:job_volumes),
    responses: %{
      ok: {"Runner volume data", "application/json", RunnerVolumes.response(:job_volumes)},
      bad_request: {"Invalid parameters", "application/json", Error},
      forbidden: {"Forbidden", "application/json", Error},
      not_found: {"Volume or job not found, or runners disabled", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  operation(:analytics,
    summary: "Get account or volume storage, activity and trends for a time range.",
    operation_id: "getRunnerVolumeAnalytics",
    parameters: RunnerVolumes.parameters(:analytics),
    responses: %{
      ok: {"Runner volume data", "application/json", RunnerVolumes.response(:analytics)},
      bad_request: {"Invalid parameters", "application/json", Error},
      forbidden: {"Forbidden", "application/json", Error},
      not_found: {"Volume or job not found, or runners disabled", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  operation(:clear,
    summary: "Clear saved volume contents. Running jobs retain their copies but cannot save them.",
    operation_id: "clearRunnerVolume",
    parameters: RunnerVolumes.parameters(:clear),
    responses: %{
      ok: {"Runner volume data", "application/json", RunnerVolumes.response(:clear)},
      bad_request: {"Invalid parameters", "application/json", Error},
      forbidden: {"Forbidden", "application/json", Error},
      not_found: {"Volume or job not found, or runners disabled", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  for action <- [:list, :show, :jobs, :job_volumes, :analytics, :clear] do
    def unquote(action)(%{assigns: %{selected_account: account}} = conn, params) do
      params = Map.new(params, fn {key, value} -> {to_string(key), value} end)
      conn = put_resp_header(conn, "cache-control", "private, no-store")

      if FeatureFlags.runners_enabled?(account) do
        respond(conn, Query.run(unquote(action), account.id, params))
      else
        conn |> put_status(:not_found) |> json(%{message: "Runners are not enabled for this account."})
      end
    end
  end

  defp respond(conn, {:ok, data}), do: json(conn, data)

  defp respond(conn, {:error, :not_found}) do
    conn |> put_status(:not_found) |> json(%{message: "Runner volume or job not found."})
  end

  defp respond(conn, {:error, :invalid_parameters}) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      message:
        "Invalid identifier, pagination, sorting or time range. Use an ordered range of at most 90 days ending no later than now."
    })
  end
end
