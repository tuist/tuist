defmodule TuistWeb.BuildControllerMixTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  alias Tuist.Mix
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  describe "timeline/2" do
    test "Mix metadata downloads authorize and scope the build before loading", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      stranger = AccountsFixtures.user_fixture()

      for source <- [:mix] do
        project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: source)
        other = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: source)
        {id, route} = recorded_build(project, source)
        path = "/#{user.account.name}/#{project.name}/builds/#{route}/#{id}/timeline.json"
        response_conn = conn |> log_in_user(user) |> get(path)
        response = json_response(response_conn, 200)
        assert response["total_count"] == 1
        assert [%{"title" => "Compile"}] = response["events"]
        refute Map.has_key?(hd(response["events"]), "log")
        refute Map.has_key?(response, "machine_metrics")
        assert get_resp_header(response_conn, "cache-control") == ["private, no-store"]

        assert_error_sent 404, fn ->
          conn |> log_in_user(stranger) |> get(path)
        end

        assert_error_sent 404, fn ->
          conn |> log_in_user(user) |> get("/#{user.account.name}/#{other.name}/builds/#{route}/#{id}/timeline.json")
        end
      end
    end
  end

  defp recorded_build(project, :mix) do
    id = UUIDv7.generate()

    {:ok, ^id} =
      Mix.create_build(%{
        id: id,
        project_id: project.id,
        account_id: project.account_id,
        duration_ms: 2000,
        status: "success",
        started_at: ~U[2026-09-09 10:00:00Z],
        files: [%{path: "lib/compile.ex", start_offset_ms: 1000, compile_duration_ms: 100, modules: ["Compile"]}]
      })

    for buffer <- [Mix.Build.Buffer, Mix.CompiledFile.Buffer], do: buffer.flush()
    {id, "build-runs"}
  end
end
