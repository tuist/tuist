defmodule TuistWeb.API.SnapshotsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import Ecto.Query

  alias Tuist.Snapshots.Image
  alias Tuist.Snapshots.Workers.ProcessBuildWorker
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  @hash String.duplicate("ab", 32)

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)
    conn = conn |> Authentication.put_current_user(user) |> put_req_header("content-type", "application/json")
    stub(Storage, :generate_upload_url, fn key, _actor, _opts -> "https://storage.test/#{key}" end)
    %{conn: conn, user: user, project: project}
  end

  defp builds_url(user, project, suffix \\ ""),
    do: "/api/projects/#{user.account.name}/#{project.name}/snapshots/builds#{suffix}"

  test "creates a build, asks for its images, and queues the comparison once they're uploaded", %{
    conn: conn,
    user: user,
    project: project
  } do
    response =
      conn
      |> post(builds_url(user, project), %{
        set: "android-phone",
        git_branch: "feature",
        git_commit_sha: String.duplicate("a", 40),
        pull_request_title: "Refresh the profile card",
        # A filtered run: Settings.png is in the suite but wasn't rendered.
        all_image_names: ["ProfileCard.png", "Settings.png"],
        images: [
          %{
            name: "ProfileCard.png",
            content_hash: @hash,
            width: 800,
            height: 400,
            display_name: "ProfileCard.Dark",
            group: "Profile",
            tags: %{"ui_mode" => "dark", "device" => "id:pixel_7"},
            diff_threshold: 0.01
          }
        ]
      })
      |> json_response(:ok)

    build_id = response["build"]["id"]

    images = Map.new(Tuist.Repo.all(Image), &{&1.name, &1})

    assert %{display_name: "ProfileCard.Dark", group: "Profile", diff_threshold: 0.01, tags: tags} =
             images["ProfileCard.png"]

    assert %{status: "skipped", content_hash: nil} = images["Settings.png"]
    assert Tuist.Repo.get!(Tuist.Snapshots.Build, build_id).pull_request_title == "Refresh the profile card"

    assert tags == %{"ui_mode" => "dark", "device" => "id:pixel_7"}
    assert response["build"]["state"] == "uploading"
    assert response["build"]["url"] =~ "/#{user.account.name}/#{project.name}/snapshots/#{build_id}"

    assert [%{"content_hash" => @hash, "url" => "https://storage.test/" <> key}] = response["uploads"]
    assert key == "#{user.account.name}/#{project.name}/snapshots/blobs/#{@hash}.png"

    stub(Storage, :object_exists?, fn _key, _actor -> false end)

    assert %{"message" => message} =
             conn |> post(builds_url(user, project, "/#{build_id}/complete")) |> json_response(:bad_request)

    # Only the uploaded image is missing, not the skipped one, which has no content yet.
    assert message =~ "1 images were not uploaded: #{@hash}"

    stub(Storage, :object_exists?, fn _key, _actor -> true end)

    assert %{"state" => "processing", "status" => "processing"} =
             conn |> post(builds_url(user, project, "/#{build_id}/complete")) |> json_response(:ok)

    assert_enqueued(worker: ProcessBuildWorker, args: %{build_id: build_id})

    assert %{"id" => ^build_id, "state" => "processing"} =
             conn |> get(builds_url(user, project, "/#{build_id}")) |> json_response(:ok)
  end

  test "another project's build is not found", %{conn: conn, user: user, project: project} do
    other = ProjectsFixtures.project_fixture()

    {:ok, build, _} =
      Tuist.Snapshots.create_build(other, %{set_name: "phone"}, [%{name: "a.png", content_hash: @hash}])

    conn |> get(builds_url(user, project, "/#{build.id}")) |> json_response(:not_found)
  end

  test "serves the checkout's baseline with a download URL per image", %{conn: conn, user: user, project: project} do
    other_hash = String.duplicate("cd", 32)
    removed_hash = String.duplicate("ef", 32)

    {:ok, build, _} =
      Tuist.Snapshots.create_build(
        project,
        %{set_name: "phone", git_branch: "main", git_commit_sha: String.duplicate("a", 40)},
        [
          %{name: "Card.png", content_hash: @hash},
          %{name: "Cards/Dark.png", content_hash: other_hash},
          %{name: "Gone.png", content_hash: removed_hash}
        ]
      )

    build |> Ecto.Changeset.change(state: "processed") |> Tuist.Repo.update!()
    Tuist.Repo.update_all(from(i in Image, where: i.name == "Gone.png"), set: [status: "removed"])
    stub(Storage, :generate_download_url, fn key, _actor, _opts -> "https://storage.test/get/#{key}" end)

    url = "/api/projects/#{user.account.name}/#{project.name}/snapshots/baseline"
    query = "?set=phone&git_commit_sha=#{String.duplicate("b", 40)}"

    response = conn |> get(url <> query) |> json_response(:ok)

    assert response["build"]["id"] == build.id
    blobs = "#{user.account.name}/#{project.name}/snapshots/blobs"

    # The removed image isn't part of the baseline.
    assert Enum.map(response["images"], &{&1["name"], &1["content_hash"], &1["url"]}) == [
             {"Card.png", @hash, "https://storage.test/get/#{blobs}/#{@hash}.png"},
             {"Cards/Dark.png", other_hash, "https://storage.test/get/#{blobs}/#{other_hash}.png"}
           ]

    # A set without a baseline yet, such as one never recorded on the default branch.
    assert %{"build" => nil, "images" => []} =
             conn |> get(url <> "?set=tablet&git_commit_sha=#{String.duplicate("b", 40)}") |> json_response(:ok)
  end
end
