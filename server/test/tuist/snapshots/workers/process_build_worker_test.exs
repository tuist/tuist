defmodule Tuist.Snapshots.Workers.ProcessBuildWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Repo
  alias Tuist.Snapshots
  alias Tuist.Snapshots.Build
  alias Tuist.Snapshots.Workers.ProcessBuildWorker
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    project = ProjectsFixtures.project_fixture(preload: [:account])
    store = :ets.new(:snapshot_objects, [:public])
    stub(Storage, :put_object, fn key, content, _actor -> :ets.insert(store, {key, content}) && :ok end)

    stub(Storage, :get_object_as_string, fn key, _actor ->
      case :ets.lookup(store, key) do
        [{_, content}] -> content
        [] -> nil
      end
    end)

    stub(Storage, :object_exists?, fn key, _actor -> :ets.member(store, key) end)
    %{project: project}
  end

  defp completed_build(project, branch, content) do
    hash = Base.encode16(:crypto.hash(:sha256, content), case: :lower)
    Storage.put_object(Snapshots.blob_key(project, hash), content, project.account)

    {:ok, build, _missing} =
      Snapshots.create_build(project, %{set_name: "phone", git_branch: branch}, [
        %{name: "a.png", content_hash: hash, width: 10, height: 10}
      ])

    {:ok, build} = Snapshots.complete_build(project, build)
    build
  end

  defp perform(build, attempt) do
    ProcessBuildWorker.perform(%Oban.Job{args: %{"build_id" => build.id}, attempt: attempt, max_attempts: 3})
  end

  test "marks the build failed when its last attempt crashes comparing an image", %{project: project} do
    {:ok, png} = 10 |> Image.new!(10, color: [255, 255, 255]) |> Image.write(:memory, suffix: ".png")
    {:ok, _baseline} = project |> completed_build("main", png) |> Snapshots.process_build()
    build = completed_build(project, "feature", "not a png")

    try do
      perform(build, 3)
    catch
      _kind, _reason -> :ok
    end

    assert %Build{state: "failed"} = Repo.get!(Build, build.id)
  end
end
