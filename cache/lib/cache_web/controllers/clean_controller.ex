defmodule CacheWeb.CleanController do
  use CacheWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Cache.CleanProjectWorker
  alias CacheWeb.API.Schemas.Error

  require Logger

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  action_fallback CacheWeb.CacheFallbackController

  tags(["Clean"])

  operation(:clean,
    summary: "Clean all cache artifacts for a project",
    operation_id: "cleanProjectCache",
    parameters: [
      account_handle: [
        in: :query,
        type: :string,
        required: true,
        description: "The handle of the account"
      ],
      project_handle: [
        in: :query,
        type: :string,
        required: true,
        description: "The handle of the project"
      ]
    ],
    responses: %{
      no_content: {"Cache cleaned successfully", nil, nil},
      unauthorized: {"Unauthorized", "application/json", Error},
      forbidden: {"Forbidden", "application/json", Error},
      internal_server_error: {"Failed to clean cache", "application/json", Error}
    }
  )

  def clean(conn, %{account_handle: account_handle, project_handle: project_handle}) do
    Logger.info("Cleaning cache for project #{account_handle}/#{project_handle}")

    {:ok, _job} =
      %{account_handle: account_handle, project_handle: project_handle}
      |> CleanProjectWorker.new()
      |> Oban.insert()

    send_resp(conn, :no_content, "")
  end
end
