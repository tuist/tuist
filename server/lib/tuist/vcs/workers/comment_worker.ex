defmodule Tuist.VCS.Workers.CommentWorker do
  @moduledoc """
  Background job for generating VCS pull request comments.

  This worker processes VCS comment generation asynchronously to improve
  API response times for the runs endpoint.
  """
  use Oban.Worker

  alias Tuist.Projects
  alias Tuist.VCS

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "build_id" => _build_id,
          "git_commit_sha" => git_commit_sha,
          "git_ref" => git_ref,
          "git_remote_url_origin" => git_remote_url_origin,
          "project_id" => project_id,
          "preview_url_template" => preview_url_template,
          "preview_qr_code_url_template" => preview_qr_code_url_template,
          "command_run_url_template" => command_run_url_template,
          "bundle_url_template" => bundle_url_template,
          "build_url_template" => build_url_template
        }
      }) do
    project = Projects.get_project_by_id(project_id)

    VCS.post_vcs_pull_request_comment(%{
      git_commit_sha: git_commit_sha,
      git_ref: git_ref,
      git_remote_url_origin: git_remote_url_origin,
      project: project,
      preview_url: &build_url(preview_url_template, &1),
      preview_qr_code_url: &build_url(preview_qr_code_url_template, &1),
      command_run_url: &build_url(command_run_url_template, &1),
      bundle_url: &build_url(bundle_url_template, &1),
      build_url: &build_url(build_url_template, &1)
    })

    :ok
  end

  defp build_url(template, data) do
    template
    |> String.replace(":account_name", data.project.account.name)
    |> String.replace(":project_name", data.project.name)
    |> replace_if_present(data, :preview, ":preview_id")
    |> replace_if_present(data, :command_event, ":command_event_id")
    |> replace_if_present(data, :bundle, ":bundle_id")
    |> replace_if_present(data, :build, ":build_id")
  end

  defp replace_if_present(template, data, key, placeholder) do
    case Map.get(data, key) do
      nil -> String.replace(template, placeholder, "")
      value -> String.replace(template, placeholder, to_string(Map.get(value, :id)))
    end
  end
end
