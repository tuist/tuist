defmodule TuistWeb.API.StackTracesController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Tests
  alias TuistWeb.API.Schemas.Error

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :test)

  tags ["Tests"]

  operation(:create,
    summary: "Upload a crash stack trace for a test run.",
    parameters: [
      account_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The handle of the project's account."
      ],
      project_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The handle of the project."
      ],
      test_run_id: [
        in: :path,
        type: :string,
        required: true,
        description: "The UUID of the test run."
      ]
    ],
    operation_id: "createStackTrace",
    request_body:
      {"Stack trace params", "application/json",
       %Schema{
         title: "StackTraceParams",
         description: "Parameters to upload a single crash stack trace.",
         type: :object,
         properties: %{
           id: %Schema{
             type: :string,
             description: "Deterministic UUID generated from content hash and file name."
           },
           file_name: %Schema{
             type: :string,
             description: "The human-readable name of the crash log file."
           },
           app_name: %Schema{
             type: :string,
             description: "The name of the crashed application."
           },
           os_version: %Schema{
             type: :string,
             description: "The OS version when the crash occurred."
           },
           exception_type: %Schema{
             type: :string,
             description: "The exception type (e.g., EXC_CRASH)."
           },
           signal: %Schema{
             type: :string,
             description: "The signal that caused the crash (e.g., SIGABRT)."
           },
           exception_subtype: %Schema{
             type: :string,
             description: "The exception subtype or additional details."
           },
           triggered_thread_frames: %Schema{
             type: :string,
             description: "Human-readable formatted crash thread frames."
           }
         },
         required: [:id, :file_name]
       }},
    responses: %{
      ok: {"The stack trace was uploaded", "application/json", nil},
      unauthorized: {"You need to be authenticated", "application/json", Error},
      forbidden: {"Not authorized to perform this action", "application/json", Error},
      not_found: {"The project doesn't exist", "application/json", Error},
      bad_request: {"The request parameters are invalid", "application/json", Error}
    }
  )

  def create(%{body_params: body_params} = conn, %{test_run_id: _test_run_id}) do
    stack_trace_params = %{
      id: body_params.id,
      file_name: body_params.file_name,
      app_name: Map.get(body_params, :app_name),
      os_version: Map.get(body_params, :os_version),
      exception_type: Map.get(body_params, :exception_type),
      signal: Map.get(body_params, :signal),
      exception_subtype: Map.get(body_params, :exception_subtype),
      triggered_thread_frames: Map.get(body_params, :triggered_thread_frames, ""),
      inserted_at: NaiveDateTime.utc_now()
    }

    case Tests.upload_stack_trace(stack_trace_params) do
      {:ok, _} ->
        conn
        |> put_status(:ok)
        |> json(%{})

      {:error, _changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{message: "The request parameters are invalid"})
    end
  end
end
