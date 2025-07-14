defmodule TuistWeb.API.QAController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.QA
  alias Tuist.VCS
  alias TuistWeb.API.Schemas.Error

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  tags ["QA"]

  operation(:update,
    summary: "Update a QA run with results.",
    operation_id: "updateQARun",
    parameters: [
      qa_run_id: [
        in: :path,
        type: :string,
        required: true,
        description: "The ID of the QA run to update."
      ]
    ],
    request_body:
      {"QA run update params", "application/json",
       %Schema{
         title: "QARunUpdateParams",
         description: "Parameters to update a QA run.",
         type: :object,
         properties: %{
           state: %Schema{
             type: :string,
             enum: ["running", "finished"],
             description: "The state of the QA run."
           },
           summary: %Schema{
             type: :string,
             description: "Summary of the QA run results."
           }
         },
         required: [:state]
       }},
    responses: %{
      ok: {"QA run updated successfully", "application/json",
           %Schema{
             type: :object,
             properties: %{
               id: %Schema{type: :string, description: "The ID of the updated QA run"},
               state: %Schema{type: :string, description: "The state of the QA run"},
               summary: %Schema{type: :string, description: "The summary of the QA run"}
             }
           }},
      not_found: {"QA run not found", "application/json", Error},
      bad_request: {"Invalid request parameters", "application/json", Error}
    }
  )

  def update(%{params: %{"qa_run_id" => qa_run_id}, body_params: body_params} = conn, _params) do
    case QA.get_qa_run(qa_run_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "QA run not found"})

      qa_run ->
        case QA.update_qa_run(qa_run, body_params) do
          {:ok, updated_qa_run} ->
            # If the state is finished and we have a summary, post a pull request comment
            if updated_qa_run.state == "finished" && updated_qa_run.summary do
              # Load the app_build and related data
              updated_qa_run = Tuist.Repo.preload(updated_qa_run, app_build: [preview: [project: :account]])
              
              if updated_qa_run.app_build && updated_qa_run.app_build.preview do
                preview = updated_qa_run.app_build.preview
                project = preview.project
                
                # Post VCS comment with QA summary
                VCS.post_vcs_pull_request_comment(%{
                  git_ref: preview.git_ref,
                  git_remote_url_origin: nil,
                  git_commit_sha: preview.git_commit_sha,
                  project: project,
                  preview_url: nil,
                  preview_qr_code_url: nil,
                  command_run_url: nil,
                  bundle_url: nil,
                  build_url: nil,
                  qa_summary: updated_qa_run.summary
                })
              end
            end

            conn
            |> put_status(:ok)
            |> json(%{
              id: updated_qa_run.id,
              state: updated_qa_run.state,
              summary: updated_qa_run.summary
            })

          {:error, changeset} ->
            conn
            |> put_status(:bad_request)
            |> json(%{message: "Invalid request parameters", errors: changeset.errors})
        end
    end
  end
end