defmodule Tuist.Bazel.ProfileUploadTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Bazel.Invocation
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

    assert :ok = ProfileUpload.stage(project, "invalid", "duplicate")
    assert %{state: "rejected", compressed: nil} = Repo.one(ProfileUpload.query(project.id, "invalid"))
    assert ProfileUpload.expire(DateTime.add(DateTime.utc_now(), 1, :day), 500) == 1
    assert ProfileUpload.state(build) == nil
  end
end
