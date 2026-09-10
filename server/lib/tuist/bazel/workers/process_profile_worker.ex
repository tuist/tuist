defmodule Tuist.Bazel.Workers.ProcessProfileWorker do
  @moduledoc "Parses profiles on the bounded Bazel artifact processor queue."
  # Staging enqueues one job atomically per accepted upload, including terminal-state retries.
  use Oban.Worker, queue: :process_bazel_tests, max_attempts: 5

  alias Tuist.Bazel.Profile
  alias Tuist.Bazel.ProfileUpload
  alias Tuist.Projects
  alias Tuist.Repo

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id, "invocation_id" => id}} = job) do
    query = ProfileUpload.query(project_id, id)

    case Repo.one(query) do
      %{state: "pending", compressed: compressed} ->
        case Projects.get_project_by_id(project_id) do
          nil ->
            {:discard, :project_not_found}

          project ->
            case Profile.ingest(project, id, compressed) do
              :ok ->
                Repo.update_all(query, set: [state: "processed", compressed: nil, updated_at: DateTime.utc_now()])
                :ok

              {:error, reason} when reason in [:invalid_profile, :profile_too_large] ->
                Logger.warning("Bazel profile #{id} for project #{project_id} rejected: #{reason}")

                Repo.update_all(query,
                  set: [state: "rejected", compressed: nil, error: to_string(reason), updated_at: DateTime.utc_now()]
                )

                {:discard, reason}
            end
        end

      _ ->
        :ok
    end
  rescue
    error ->
      if job.attempt >= job.max_attempts do
        Repo.update_all(ProfileUpload.query(project_id, id),
          set: [state: "failed", compressed: nil, error: "processing_failed", updated_at: DateTime.utc_now()]
        )
      end

      reraise error, __STACKTRACE__
  end
end
