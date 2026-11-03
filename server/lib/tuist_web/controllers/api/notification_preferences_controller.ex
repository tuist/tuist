defmodule TuistWeb.API.NotificationPreferencesController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.Push
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.Authentication

  plug(TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_message: TuistWeb.RenderAPIErrorPlug
  )

  plug :no_store
  plug :load_user

  tags ["Notification preferences"]

  @kind_parameter [
    in: :path,
    type: :string,
    required: true,
    description: "The notification kind. `new_preview` covers new previews of the user's projects."
  ]

  @preferences %Schema{
    title: "NotificationPreferences",
    description:
      "The signed-in user's own choices for one notification kind, per account (their personal account and organizations) with project overrides.",
    type: :object,
    properties: %{
      kind: %Schema{type: :string},
      accounts: %Schema{
        type: :array,
        items: %Schema{
          title: "NotificationPreferencesAccount",
          type: :object,
          properties: %{
            handle: %Schema{type: :string, description: "The account handle."},
            enabled: %Schema{
              type: :boolean,
              description: "The user's choice for the account's projects, including future ones."
            },
            projects: %Schema{
              type: :array,
              items: %Schema{
                title: "NotificationPreferencesProject",
                type: :object,
                properties: %{
                  handle: %Schema{type: :string, description: "The project handle, without the account."},
                  setting: %Schema{
                    type: :string,
                    enum: ["default", "on", "off"],
                    description: "`default` follows the account; `on` and `off` override it."
                  },
                  enabled: %Schema{type: :boolean, description: "Whether the user is notified about this project."}
                },
                required: [:handle, :setting, :enabled]
              }
            }
          },
          required: [:handle, :enabled, :projects]
        }
      }
    },
    required: [:kind, :accounts]
  }

  @responses %{
    ok: {"The user's preferences for the kind", "application/json", @preferences},
    unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
    forbidden: {"Only users have notification preferences", "application/json", Error},
    not_found: {"The kind, account or project was not found", "application/json", Error}
  }

  operation(:show,
    summary: "Gets the signed-in user's preferences for a notification kind",
    operation_id: "getNotificationPreferences",
    parameters: [kind: @kind_parameter],
    responses: @responses
  )

  def show(%{path_params: %{"kind" => kind}} = conn, _params) do
    with {:ok, preferences} <- preferences(conn, kind) do
      json(conn, preferences_json(kind, preferences))
    end
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
         additionalProperties: false,
         properties: %{enabled: %Schema{type: :boolean}},
         required: [:enabled]
       }},
    responses: @responses
  )

  def update_account(%{path_params: %{"kind" => kind, "account_handle" => handle}, body_params: body} = conn, _params) do
    user = conn.assigns.preferences_user

    with {:ok, preferences} <- preferences(conn, kind),
         %{account: account} <- Enum.find(preferences, &(&1.account.name == handle)) || not_found(conn),
         :ok <- Push.update_account_preference(user, kind, account.id, body.enabled) do
      json(conn, preferences_json(kind, Push.preferences(user, kind)))
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
         additionalProperties: false,
         properties: %{
           setting: %Schema{
             type: :string,
             enum: ["default", "on", "off"],
             description: "`default` follows the account; `on` and `off` override it."
           }
         },
         required: [:setting]
       }},
    responses: @responses
  )

  def update_project(
        %{
          path_params: %{"kind" => kind, "account_handle" => account_handle, "project_handle" => project_handle},
          body_params: body
        } = conn,
        _params
      ) do
    user = conn.assigns.preferences_user

    with {:ok, preferences} <- preferences(conn, kind),
         %{project: project} <- find_project(preferences, account_handle, project_handle) || not_found(conn),
         :ok <- Push.update_project_preference(user, kind, project.id, override(body.setting)) do
      json(conn, preferences_json(kind, Push.preferences(user, kind)))
    end
  end

  defp preferences(conn, kind) do
    if kind in Push.preference_kinds(),
      do: {:ok, Push.preferences(conn.assigns.preferences_user, kind)},
      else: not_found(conn)
  end

  defp find_project(preferences, account_handle, project_handle) do
    Enum.find_value(preferences, fn %{account: account, projects: projects} ->
      account.name == account_handle && Enum.find(projects, &(&1.project.name == project_handle))
    end)
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

  defp load_user(conn, _opts) do
    case Authentication.authenticated_subject(conn) do
      %User{} = user ->
        assign(conn, :preferences_user, user)

      %AuthenticatedAccount{issued_by: %User{} = user} ->
        assign(conn, :preferences_user, user)

      _ ->
        conn
        |> put_status(:forbidden)
        |> json(%{message: "Notification preferences belong to a signed-in user."})
        |> halt()
    end
  end

  defp no_store(conn, _opts), do: put_resp_header(conn, "cache-control", "no-store")
end
