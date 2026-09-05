defmodule TuistWeb.BazelInvocationLogsController do
  use TuistWeb, :controller

  alias Tuist.Bazel
  alias Tuist.Projects
  alias TuistWeb.Errors.NotFoundError

  @batch_size 1_000

  def download(conn, %{
        "account_handle" => account_handle,
        "project_handle" => project_handle,
        "invocation_id" => invocation_id
      }) do
    with {:ok, project} <-
           Projects.get_project_by_slug("#{account_handle}/#{project_handle}", preload: [:account]),
         {:ok, invocation} <- Bazel.get_invocation(project.id, invocation_id, include_cache_summary: false),
         query_options = Bazel.invocation_log_query_options(invocation),
         logs when logs != [] <- list_logs(project.id, invocation_id, nil, query_options) do
      conn =
        conn
        |> put_resp_content_type("text/plain")
        |> put_resp_header("content-disposition", ~s(attachment; filename="bazel-invocation.log"))
        |> send_chunked(:ok)

      stream_log_batches(conn, project.id, invocation_id, logs, query_options)
    else
      _ ->
        raise NotFoundError, dgettext("dashboard_projects", "Bazel invocation logs not found.")
    end
  end

  defp stream_log_batches(conn, project_id, invocation_id, logs, query_options) do
    case chunk(conn, Enum.map_join(logs, "", & &1.message)) do
      {:ok, conn} when length(logs) == @batch_size ->
        next_logs = list_logs(project_id, invocation_id, List.last(logs).sequence_number, query_options)

        if next_logs == [] do
          conn
        else
          stream_log_batches(conn, project_id, invocation_id, next_logs, query_options)
        end

      {:ok, conn} ->
        conn

      {:error, _reason} ->
        conn
    end
  end

  defp list_logs(project_id, invocation_id, after_sequence_number, query_options) do
    Bazel.list_invocation_log_batch(
      project_id,
      invocation_id,
      after_sequence_number,
      @batch_size,
      query_options
    )
  end
end
