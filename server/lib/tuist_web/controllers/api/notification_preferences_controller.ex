defmodule TuistWeb.API.NotificationPreferencesController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Notifications
  alias Tuist.Projects
  alias Tuist.Projects.Project
  alias TuistWeb.API.Responses
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.NotificationPreferences

  # Reject other credentials before validating their requests.
  plug TuistWeb.Plugs.AppSessionPlug

  plug(TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_message: TuistWeb.RenderAPIErrorPlug
  )

  tags ["Notification preferences"]

  @kind_parameter [
    in: :path,
    type: :string,
    required: true,
    description: "The notification kind. `new_preview` covers new previews of the user's projects."
  ]

  @responses %{
    ok: {"The user's preferences for the kind", "application/json", NotificationPreferences},
    unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
    forbidden: {"Only the signed-in Tuist app can manage notification preferences", "application/json", Error},
    not_found:
      {"The kind, account or project was not found. Servers return 404 for kinds they don't offer.", "application/json",
       Error}
  }

  @write_responses Map.put(@responses, :too_many_requests, Responses.app_writes_throttled())

  operation(:show,
    summary: "Gets the signed-in user's preferences for a notification kind",
    operation_id: "getNotificationPreferences",
    parameters: [kind: @kind_parameter],
    responses: @responses
  )

  def show(%{path_params: %{"kind" => kind}} = conn, _params) do
    if kind in Notifications.kinds(),
      do: json(conn, preferences_json(kind, Notifications.preferences(conn.assigns.app_user, kind))),
      else: not_found(conn)
  end

  operation(:update_account,
    summary: "Turns a notification kind on or off for an account's projects",
    operation_id: "updateAccountNotificationPreference",
    parameters: [
      kind: @kind_parameter,
      account_handle: [in: :path, type: :string, required: true, description: "The account handle."]
    ],
    request_body:
      {"Account preference", "application/json",
       %Schema{
         type: :object,
         properties: %{enabled: %Schema{type: :boolean}},
         required: [:enabled]
       }, required: true},
    responses: @write_responses
  )

  def update_account(%{path_params: %{"kind" => kind, "account_handle" => handle}, body_params: body} = conn, _params) do
    user = conn.assigns.app_user

    # The context only accepts the user's own accounts, so foreign and unknown
    # handles both answer 404.
    with %Account{id: account_id} <- Accounts.get_account_by_handle(handle),
         :ok <- Notifications.update_account_preference(user, kind, account_id, body.enabled) do
      json(conn, preferences_json(kind, Notifications.preferences(user, kind)))
    else
      _ -> not_found(conn)
    end
  end

  operation(:update_project,
    summary: "Overrides a notification kind for one project",
    operation_id: "updateProjectNotificationPreference",
    parameters: [
      kind: @kind_parameter,
      account_handle: [in: :path, type: :string, required: true, description: "The account handle."],
      project_handle: [in: :path, type: :string, required: true, description: "The project handle."]
    ],
    request_body:
      {"Project preference", "application/json",
       %Schema{
         type: :object,
         properties: %{
           setting: %Schema{
             type: :string,
             enum: ["default", "on", "off"],
             description: "`default` follows the account; `on` and `off` override it."
           }
         },
         required: [:setting]
       }, required: true},
    responses: @write_responses
  )

  def update_project(
        %{
          path_params: %{"kind" => kind, "account_handle" => account_handle, "project_handle" => project_handle},
          body_params: body
        } = conn,
        _params
      ) do
    user = conn.assigns.app_user

    with %Project{id: project_id} <-
           Projects.get_project_by_account_and_project_handles(account_handle, project_handle),
         :ok <- Notifications.update_project_preference(user, kind, project_id, override(body.setting)) do
      json(conn, preferences_json(kind, Notifications.preferences(user, kind)))
    else
      _ -> not_found(conn)
    end
  end

  defp not_found(conn) do
    conn |> put_status(:not_found) |> json(%{message: "Not found."})
  end

  defp override("default"), do: nil
  defp override("on"), do: true
  defp override("off"), do: false

  defp preferences_json(kind, preferences) do
    %{
      kind: kind,
      accounts:
        Enum.map(preferences, fn %{account: account, enabled: enabled, projects: projects} ->
          %{
            handle: account.name,
            enabled: enabled,
            projects:
              Enum.map(projects, fn %{project: project, override: override, enabled: enabled} ->
                %{handle: project.name, setting: setting(override), enabled: enabled}
              end)
          }
        end)
    }
  end

  defp setting(nil), do: "default"
  defp setting(true), do: "on"
  defp setting(false), do: "off"
end
