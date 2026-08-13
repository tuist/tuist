defmodule Tuist.Atlas.Artifacts do
  @moduledoc """
  Resolves a stored artifact to a short-lived presigned download URL for the
  internal Atlas workload.

  Atlas runs in its own cluster with no credentials for the artifact buckets, so
  it cannot reach object storage on its own. Support escalations, however, are
  usually about the artifact rather than the row: the `.xcresult` bundle behind a
  failed test run, the crash report attached to a test case run, the
  `.xcactivitylog` behind a slow build. This module maps a record id to the key
  its artifact lives under and presigns a download for it — the same key builders
  the product paths use, so a drift in one shows up in both.

  Each kind is looked up before it is presigned, so a caller learns the
  difference between "no such run" (`:not_found`) and "the run exists but its
  artifact was never uploaded or has since been pruned" (`:object_not_found`),
  which is the distinction that usually resolves the escalation.
  """

  alias Tuist.AppBuilds
  alias Tuist.Builds
  alias Tuist.CommandEvents
  alias Tuist.Projects
  alias Tuist.Storage
  alias Tuist.Tests

  @default_expires_in 900
  @max_expires_in 3600

  @kinds ~w(test_run_result_bundle test_run_session test_case_run_attachment build_archive preview_app_build)

  @doc "The artifact kinds `presign/3` accepts."
  def kinds, do: @kinds

  @doc """
  Presigns a download for the artifact of `kind` belonging to the record `id`.

  `:expires_in` is the URL lifetime in seconds, defaulting to
  #{@default_expires_in} and clamped to #{@max_expires_in}.
  """
  def presign(kind, id, opts \\ [])

  def presign(kind, id, opts) when kind in @kinds and is_binary(id) do
    with {:ok, project, object_key} <- resolve(kind, id),
         {:ok, byte_size} <- object_size(object_key, project.account) do
      expires_in = expires_in(Keyword.get(opts, :expires_in))

      {:ok,
       %{
         kind: kind,
         id: id,
         account_handle: project.account.name,
         project_handle: project.name,
         object_key: object_key,
         byte_size: byte_size,
         download_url: download_url(object_key, project.account, expires_in),
         expires_at: DateTime.utc_now() |> DateTime.add(expires_in, :second) |> DateTime.truncate(:second)
       }}
    end
  end

  def presign(kind, _id, _opts) when kind in @kinds, do: {:error, :not_found}
  def presign(_kind, _id, _opts), do: {:error, :unknown_kind}

  # Both the command-event and run-scoped key builders resolve to
  # `<account>/<project>/runs/<id>/…`, so the id is the only thing that differs
  # between a legacy `tuist test` command event and a remote-processed
  # `tuist inspect test` run. Look the id up as a test run first and fall back to
  # a command event, then let the shared builder produce the key.
  defp resolve("test_run_result_bundle", id) do
    with {:ok, project} <- test_run_project(id) do
      {:ok, project, CommandEvents.get_result_bundle_key(id, project)}
    end
  end

  defp resolve("test_run_session", id) do
    with {:ok, project} <- test_run_project(id) do
      {:ok, project, CommandEvents.get_session_key(id, project)}
    end
  end

  defp resolve("test_case_run_attachment", id) do
    with {:ok, uuid} <- cast_uuid(id),
         {:ok, attachment} <- Tests.get_attachment_by_id(uuid),
         {:ok, test_case_run} <- Tests.get_test_case_run_by_id(attachment.test_case_run_id),
         {:ok, project} <- project_with_account(test_case_run.project_id) do
      object_key =
        Tests.attachment_storage_key(%{
          account_handle: project.account.name,
          project_handle: project.name,
          test_run_id: attachment.test_run_id,
          test_case_run_id: attachment.test_case_run_id,
          attachment_id: attachment.id,
          file_name: attachment.file_name
        })

      {:ok, project, object_key}
    end
  end

  defp resolve("build_archive", id) do
    with {:ok, build} <- Builds.get_build(id),
         {:ok, project} <- project_with_account(build.project_id) do
      {:ok, project, Builds.build_storage_key(project.account.name, project.name, build.id)}
    end
  end

  defp resolve("preview_app_build", id) do
    with {:ok, app_build} <- app_build(id) do
      project = app_build.preview.project

      object_key =
        AppBuilds.storage_key(%{
          account_handle: project.account.name,
          project_handle: project.name,
          app_build: app_build
        })

      {:ok, project, object_key}
    end
  end

  defp test_run_project(id) do
    case Tests.get_test(id) do
      {:ok, test} ->
        project_with_account(test.project_id)

      {:error, :not_found} ->
        with {:ok, command_event} <- CommandEvents.get_command_event_by_id(id) do
          CommandEvents.get_project_for_command_event(command_event, preload: :account)
        end
    end
  end

  # `app_build_by_id/2` answers a malformed id with a message rather than
  # `:not_found`; the caller only cares that nothing was found.
  defp app_build(id) do
    case AppBuilds.app_build_by_id(id, preload: [preview: [project: :account]]) do
      {:ok, %{preview: %{project: %{account: _account}}} = app_build} -> {:ok, app_build}
      _other -> {:error, :not_found}
    end
  end

  # The attachment lookup queries a UUID column directly, which raises on a
  # malformed value instead of returning nothing.
  defp cast_uuid(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :not_found}
    end
  end

  defp project_with_account(project_id) do
    case Projects.get_project_by_id(project_id) do
      nil -> {:error, :not_found}
      project -> {:ok, project}
    end
  end

  defp object_size(object_key, account) do
    case Storage.get_object_size(object_key, account) do
      {:ok, byte_size} -> {:ok, byte_size}
      {:error, :not_found} -> {:error, :object_not_found}
      {:error, _reason} -> {:error, :storage_unavailable}
    end
  end

  defp download_url(object_key, account, expires_in) do
    Storage.generate_download_url(object_key, account,
      expires_in: expires_in,
      content_disposition: ~s(attachment; filename="#{Path.basename(object_key)}")
    )
  end

  defp expires_in(seconds) when is_integer(seconds) and seconds > 0, do: min(seconds, @max_expires_in)
  defp expires_in(_seconds), do: @default_expires_in
end
