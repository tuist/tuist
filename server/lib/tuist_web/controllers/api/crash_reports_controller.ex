defmodule TuistWeb.API.CrashReportsController do
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
    summary: "Upload a crash report for a test case run.",
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
      ]
    ],
    operation_id: "createCrashReport",
    request_body:
      {"Crash report params", "application/json",
       %Schema{
         title: "CrashReportParams",
         description: "Parameters to upload a single crash report.",
         type: :object,
         properties: %{
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
           },
           test_case_run_id: %Schema{
             type: :string,
             description: "The UUID of the test case run this crash report belongs to."
           },
           test_case_run_attachment_id: %Schema{
             type: :string,
             description: "The UUID of the test case run attachment this crash report was parsed from."
           }
         },
         required: [:test_case_run_id, :test_case_run_attachment_id]
       }},
    responses: %{
      ok: {"The crash report was uploaded", "application/json", nil},
      unauthorized: {"You need to be authenticated", "application/json", Error},
      forbidden: {"Not authorized to perform this action", "application/json", Error},
      not_found: {"The project doesn't exist", "application/json", Error},
      bad_request: {"The request parameters are invalid", "application/json", Error}
    }
  )

  def create(%{body_params: body_params} = conn, _params) do
    crash_report_params = %{
      id: UUIDv7.generate(),
      exception_type: Map.get(body_params, :exception_type),
      signal: Map.get(body_params, :signal),
      exception_subtype: Map.get(body_params, :exception_subtype),
      triggered_thread_frames: Map.get(body_params, :triggered_thread_frames, ""),
      test_case_run_id: body_params.test_case_run_id,
      test_case_run_attachment_id: body_params.test_case_run_attachment_id,
      inserted_at: NaiveDateTime.utc_now()
    }

    {:ok, _} = Tests.upload_crash_report(crash_report_params)

    conn
    |> put_status(:ok)
    |> json(%{})
  end
end
