defmodule TuistWeb.API.AppLogsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.AppLogs
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.Authentication
  alias TuistWeb.RateLimit

  require Logger

  plug(TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  tags ["AppLogs"]

  @rate_limit 30
  @rate_limit_window to_timeout(minute: 1)

  operation(:create,
    summary: "Upload Tuist app logs",
    description:
      "Uploads a batch of diagnostic log lines from the Tuist iOS or macOS app so the Tuist team can investigate issues without asking users to export logs.",
    operation_id: "uploadAppLogs",
    request_body:
      {"App logs", "application/json",
       %Schema{
         title: "AppLogsUpload",
         type: :object,
         properties: %{
           app: %Schema{
             type: :object,
             properties: %{
               platform: %Schema{type: :string, enum: ["ios", "macos"], description: "The app's platform."},
               version: %Schema{type: :string, maxLength: 64, description: "The app's marketing version."},
               build: %Schema{type: :string, maxLength: 64, description: "The app's build number."},
               os_version: %Schema{type: :string, maxLength: 128, description: "The operating system version."}
             },
             required: [:platform, :version, :build]
           },
           entries: %Schema{
             type: :array,
             maxItems: 1000,
             items: %Schema{
               type: :object,
               properties: %{
                 timestamp: %Schema{type: :string, format: :"date-time", description: "When the line was logged."},
                 level: %Schema{
                   type: :string,
                   enum: ["trace", "debug", "info", "notice", "warning", "error", "critical"],
                   description: "The log level."
                 },
                 source: %Schema{type: :string, maxLength: 256, description: "The module that logged the line."},
                 message: %Schema{type: :string, maxLength: 8192, description: "The redacted log message."},
                 launch_id: %Schema{
                   type: :string,
                   maxLength: 64,
                   description: "Identifies the app launch that logged the line."
                 }
               },
               required: [:timestamp, :level, :source, :message]
             }
           }
         },
         required: [:app, :entries]
       }},
    responses: %{
      accepted: "The logs were accepted",
      bad_request: {"The request body is invalid", "application/json", Error},
      unauthorized: {"You need to be authenticated", "application/json", Error},
      forbidden: {"Only users can upload app logs", "application/json", Error},
      too_many_requests: {"Too many uploads", "application/json", Error},
      service_unavailable: {"The logs could not be forwarded", "application/json", Error}
    }
  )

  def create(%{body_params: %{app: app, entries: entries}} = conn, _params) do
    case Authentication.current_user(conn) do
      nil ->
        conn
        |> put_status(:forbidden)
        |> json(%{message: "Only users can upload app logs."})

      user ->
        case RateLimit.hit("app_logs:user:#{user.id}", limit: @rate_limit, window: @rate_limit_window) do
          {:allow, _count} ->
            forward(conn, user, app, entries)

          {:deny, _limit} ->
            conn
            |> put_status(:too_many_requests)
            |> json(%{message: "Too many log uploads. Please try again later."})
        end
    end
  end

  defp forward(conn, user, app, entries) do
    case AppLogs.forward(user, app, entries) do
      :ok ->
        send_resp(conn, :accepted, "")

      {:error, reason} ->
        Logger.warning("Failed to forward app logs: #{inspect(reason)}")

        conn
        |> put_status(:service_unavailable)
        |> json(%{message: "The logs could not be forwarded."})
    end
  end
end
