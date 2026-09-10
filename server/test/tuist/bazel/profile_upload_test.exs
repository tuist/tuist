defmodule Tuist.Bazel.ProfileUploadTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Bazel.Invocation
  alias Tuist.Bazel.Profile
  alias Tuist.Bazel.ProfileUpload
  alias Tuist.Bazel.Workers.ProcessProfileWorker
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  test "invalid compressed profiles are durably rejected and their raw bytes removed" do
    project = ProjectsFixtures.project_fixture(build_system: :bazel)
    assert :ok = ProfileUpload.stage(project, "invalid", "bad gzip")
    build = %Invocation{project_id: project.id, invocation_id: "invalid"}
    assert ProfileUpload.state(build) == "pending"

    assert {:discard, :invalid_profile} =
             ProcessProfileWorker.perform(%Oban.Job{args: %{"project_id" => project.id, "invocation_id" => "invalid"}})

    assert %{state: "rejected", compressed: nil, error: "invalid_profile"} =
             Repo.one(ProfileUpload.query(project.id, "invalid"))

    assert :ok = ProfileUpload.stage(project, "invalid", valid_profile("invalid"))
    assert %{state: "pending", error: nil} = Repo.one(ProfileUpload.query(project.id, "invalid"))

    assert :ok =
             ProcessProfileWorker.perform(%Oban.Job{args: %{"project_id" => project.id, "invocation_id" => "invalid"}})

    assert %{state: "processed", compressed: nil} = Repo.one(ProfileUpload.query(project.id, "invalid"))
    assert is_binary(Profile.steps_version(build))
    assert ProfileUpload.expire(DateTime.add(DateTime.utc_now(), 1, :day), 500) == 1
    assert ProfileUpload.state(build) == nil
  end

  test "restaging failed uploads creates fresh work while duplicate pending and processed uploads are unchanged" do
    project = ProjectsFixtures.project_fixture(build_system: :bazel)
    body = valid_profile("retry")
    assert :ok = ProfileUpload.stage(project, "retry", body)
    assert :ok = ProfileUpload.stage(project, "retry", "duplicate")
    assert %{compressed: ^body, state: "pending"} = Repo.one(ProfileUpload.query(project.id, "retry"))
    assert length(all_enqueued(worker: ProcessProfileWorker)) == 1

    Repo.update_all(ProfileUpload.query(project.id, "retry"),
      set: [state: "failed", compressed: nil, error: "processing_failed"]
    )

    assert :ok = ProfileUpload.stage(project, "retry", body)
    assert length(all_enqueued(worker: ProcessProfileWorker)) == 2
    assert %{compressed: ^body, state: "pending", error: nil} = Repo.one(ProfileUpload.query(project.id, "retry"))
    assert :ok = ProcessProfileWorker.perform(%Oban.Job{args: %{"project_id" => project.id, "invocation_id" => "retry"}})
    assert :ok = ProfileUpload.stage(project, "retry", "duplicate after success")
    assert %{state: "processed", compressed: nil} = Repo.one(ProfileUpload.query(project.id, "retry"))
    assert length(all_enqueued(worker: ProcessProfileWorker)) == 2
  end

  defp valid_profile(id) do
    :zlib.gzip(
      JSON.encode!(%{otherData: %{build_id: id}, traceEvents: [%{ph: "X", name: "Compile", ts: 1000, dur: 1000}]})
    )
  end
end
