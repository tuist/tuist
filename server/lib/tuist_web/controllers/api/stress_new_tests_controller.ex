defmodule TuistWeb.API.StressNewTestsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Tests.StressNewTests
  alias TuistWeb.API.Responses
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.Tests.StressNewTestsVerdict

  plug(TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :test)

  tags ["Tests"]

  operation(:verdict,
    summary: "Decide which of a run's test cases the stress gate for newly added tests should rerun.",
    description:
      "Given the test cases a run just executed, returns the ones that have not run in CI on the project's default branch in the trailing ninety days, each with the number of repetitions its duration earns on the project's curve, plus the guard that fired if one did and the parameters the pass runs under.",
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
    operation_id: "createStressNewTestsVerdict",
    request_body:
      {"Stress verdict params", "application/json",
       %Schema{
         title: "StressNewTestsVerdictParams",
         type: :object,
         properties: %{
           test_cases: %Schema{
             type: :array,
             description:
               "The test cases that executed and were not skipped, with the duration the run measured for each.",
             items: %Schema{
               type: :object,
               properties: %{
                 name: %Schema{type: :string, description: "The name of the test case."},
                 suite_name: %Schema{type: :string, nullable: true, description: "The suite (class) of the test case."},
                 module_name: %Schema{
                   type: :string,
                   description: "The module (target or Gradle project) of the test case."
                 },
                 duration: %Schema{
                   type: :integer,
                   nullable: true,
                   description: "Duration of the test case in milliseconds."
                 }
               },
               required: [:name, :module_name]
             }
           }
         },
         required: [:test_cases]
       }},
    responses: %{
      ok: {"The verdict", "application/json", StressNewTestsVerdict},
      unauthorized: {"You need to be authenticated to request a verdict", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      too_many_requests: Responses.authorization_throttled(),
      not_found: {"The project doesn't exist", "application/json", Error},
      bad_request: {"The request parameters are invalid", "application/json", Error}
    }
  )

  def verdict(%{assigns: %{selected_project: selected_project}, body_params: body_params} = conn, _params) do
    verdict = StressNewTests.verdict(selected_project, body_params.test_cases)

    conn
    |> put_status(:ok)
    |> json(verdict)
  end
end
