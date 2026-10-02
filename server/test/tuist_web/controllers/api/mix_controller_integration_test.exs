defmodule TuistWeb.API.MixControllerIntegrationTest do
  # End-to-end: drives TuistEx.Analytics.CompileReporter with synthetic
  # Mix compiler diagnostics, has it POST through the real /mix/builds
  # controller (no Tuist.Mix mock), and asserts that ClickHouse ends up
  # with the build row and one diagnostic per captured issue.
  use TuistTestSupport.Cases.ConnCase, async: false

  import Ecto.Query
  import Phoenix.ConnTest

  alias Tuist.Builds.BuildMachineMetric
  alias Tuist.ClickHouseRepo
  alias Tuist.Mix.Build
  alias Tuist.Mix.Diagnostic
  alias Tuist.Mix.Step
  alias Tuist.Mix.Timeline
  alias TuistEx.Analytics.CompileReporter
  alias TuistEx.Analytics.MachineMetrics
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  @endpoint TuistWeb.Endpoint

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)

    conn =
      conn
      |> Authentication.put_current_user(user)
      |> put_req_header("content-type", "application/json")

    on_exit(fn ->
      case Process.whereis(CompileReporter) do
        pid when is_pid(pid) ->
          try do
            GenServer.stop(pid)
          catch
            :exit, _ -> :ok
          end

        _ ->
          :ok
      end
    end)

    %{conn: conn, user: user, project: project}
  end

  defp submit_via_controller(conn, account, project) do
    fn payload, _opts ->
      response = post(conn, "/api/projects/#{account}/#{project}/mix/builds", payload)

      case response.status do
        status when status in 200..299 -> :ok
        status -> {:error, {:http, status, response.resp_body}}
      end
    end
  end

  test "posts a compile run and lands the build + one diagnostic row in ClickHouse", %{
    conn: conn,
    user: user,
    project: project
  } do
    submit = submit_via_controller(conn, user.account.name, project.name)
    parent = self()

    shell = fn message ->
      send(parent, {:shell, message})
      :ok
    end

    {:ok, _pid} = CompileReporter.start_link(submit: submit, shell: shell)

    CompileReporter.record(
      :elixir,
      {:ok,
       [
         %{
           severity: :warning,
           file: "lib/greeter.ex",
           source: Greeter,
           message: "unused variable name",
           position: {12, 5}
         },
         %{
           severity: :error,
           file: "lib/greeter.ex",
           source: Greeter,
           message: "undefined function greet/1",
           position: 20
         }
       ]}
    )

    :ok =
      CompileReporter.finish(
        [
          %{path: "lib/macros.ex", compile_duration_ms: 300, wait_duration_ms: 0, modules: ["Macros"], waits: []},
          %{
            path: "lib/greeter.ex",
            compile_duration_ms: 70,
            wait_duration_ms: 333,
            modules: ["Greeter"],
            dependencies: [%{path: "lib/macros.ex", kind: "compile"}],
            waits: [%{module: "Macros", path: "lib/macros.ex", kind: "module", duration_ms: 333}]
          }
        ],
        [
          %{
            category: "type_check",
            title: "Type checking Greeter",
            path: "lib/greeter.ex",
            start_offset_ms: 410,
            duration_ms: 9
          }
        ]
      )

    refute_receive {:shell, _}, 500

    builds =
      ClickHouseRepo.all(
        from(b in Build,
          where: b.project_id == ^project.id
        )
      )

    assert [build] = builds
    assert build.status == "failure"
    assert build.diagnostics_error_count == 1
    assert build.diagnostics_warning_count == 1
    assert is_binary(build.elixir_version)
    assert build.elixir_version != ""

    diagnostics =
      ClickHouseRepo.all(
        from(d in Diagnostic,
          where: d.build_id == ^build.id,
          order_by: [asc: d.severity]
        )
      )

    assert length(diagnostics) == 2

    warning = Enum.find(diagnostics, &(&1.severity == "warning"))
    error = Enum.find(diagnostics, &(&1.severity == "error"))

    assert warning.file == "lib/greeter.ex"
    assert warning.module == "Greeter"
    assert warning.message == "unused variable name"
    assert warning.line == 12
    assert warning.column == 5
    assert warning.compiler == "elixir"

    assert error.file == "lib/greeter.ex"
    assert error.message == "undefined function greet/1"
    assert error.line == 20

    assert %{total: 2, rows: [greeter_file, macros_file]} = Tuist.Mix.compiled_files_page(build, sort_by: "name")
    assert greeter_file.compile_dependencies_count == 1
    assert macros_file.compile_dependents_count == 1

    assert [%{category: "type_check", title: "Type checking Greeter", path: "lib/greeter.ex", duration_ms: 9}] =
             ClickHouseRepo.all(from(s in Step, where: s.build_id == ^build.id))
  end

  test "persists ci_host, custom_metadata, and machine_metrics rows", %{
    conn: conn,
    user: user,
    project: project
  } do
    submit = submit_via_controller(conn, user.account.name, project.name)
    parent = self()

    shell = fn message ->
      send(parent, {:shell, message})
      :ok
    end

    environment = fn
      "TUIST_TAGS" -> "nightly"
      "TUIST_VALUES" -> "ticket=PROJ-42"
      "GITHUB_ACTIONS" -> "true"
      "GITHUB_SERVER_URL" -> "https://github.acme.example"
      _ -> nil
    end

    # `sampler: nil` disables the periodic sampler so the test injects a known
    # machine-metric sample directly.
    {:ok, pid} =
      CompileReporter.start_link(
        submit: submit,
        shell: shell,
        sampler: nil,
        environment: environment,
        tag: "release"
      )

    send(pid, {:machine_metric, MachineMetrics.sample(fn -> 1_700_000_000.0 end)})
    CompileReporter.record(:elixir, {:ok, []})
    :ok = CompileReporter.finish()

    refute_receive {:shell, _}, 500

    assert [build] =
             ClickHouseRepo.all(from(b in Build, where: b.project_id == ^project.id))

    assert build.ci_host == "https://github.acme.example"
    assert "nightly" in build.custom_tags
    assert "release" in build.custom_tags
    assert build.custom_values["ticket"] == "PROJ-42"

    metrics =
      ClickHouseRepo.all(from(m in BuildMachineMetric, where: m.mix_build_id == ^build.id))

    assert length(metrics) == 1
    [metric] = metrics
    assert metric.timestamp == 1_700_000_000.0
  end

  describe "a build identifier chosen by the client" do
    defp minimal(id, extra \\ %{}), do: Map.merge(%{id: id, duration_ms: 10, status: "success"}, extra)

    test "can be the same as another project's without either seeing the other's data", %{
      conn: conn,
      user: user,
      project: project
    } do
      other_user = AccountsFixtures.user_fixture(preload: [:account])
      other_project = ProjectsFixtures.project_fixture(account_id: other_user.account.id)
      id = UUIDv7.generate()
      started_at = ~U[2026-09-09 10:00:00.000000Z]

      sample = fn cpu ->
        %{timestamp: 1_788_948_001.0, cpu_usage_percent: cpu, memory_used_bytes: 1, memory_total_bytes: 2}
      end

      {:ok, ^id} =
        Tuist.Mix.create_build(%{
          id: id,
          project_id: other_project.id,
          account_id: other_user.account.id,
          duration_ms: 10,
          status: "failure",
          started_at: started_at,
          diagnostics: [%{severity: "error", file: "lib/secret.ex", message: "private detail"}],
          files: [%{path: "lib/secret.ex", start_offset_ms: 0, compile_duration_ms: 5, modules: ["Secret"]}],
          machine_metrics: [sample.(91.0)]
        })

      report =
        minimal(id, %{
          started_at: DateTime.to_iso8601(started_at),
          files: [%{path: "lib/mine.ex", start_offset_ms: 0, compile_duration_ms: 5}],
          machine_metrics: [sample.(12.0)]
        })

      assert json_response(post(conn, "/api/projects/#{user.account.name}/#{project.name}/mix/builds", report), 201)

      for buffer <- [Build.Buffer, Diagnostic.Buffer, Tuist.Mix.CompiledFile.Buffer, BuildMachineMetric.Buffer],
          do: buffer.flush()

      {:ok, mine} = Tuist.Mix.get_build(id, project_id: project.id)
      {:ok, theirs} = Tuist.Mix.get_build(id, project_id: other_project.id)

      assert Tuist.Mix.list_diagnostics(mine) == []
      assert %{rows: [%{name: "lib/mine.ex"}]} = Tuist.Mix.compiled_files_page(mine)
      assert %{rows: [%{name: "lib/secret.ex"}]} = Tuist.Mix.compiled_files_page(theirs)

      # Machine samples too: each build's timeline holds only its own.
      assert [%{cpu_usage_percent: 12.0}] = Timeline.load(mine).machine_metrics
      assert [%{cpu_usage_percent: 91.0}] = Timeline.load(theirs).machine_metrics
      assert [%{cpu_usage_percent: 12.0}] = Tuist.Mix.list_machine_metrics(mine)
    end

    test "is accepted again from the same project without storing the build twice", %{
      conn: conn,
      user: user,
      project: project
    } do
      id = UUIDv7.generate()
      path = "/api/projects/#{user.account.name}/#{project.name}/mix/builds"
      report = minimal(id, %{files: [%{path: "lib/a.ex", compile_duration_ms: 5}]})

      assert json_response(post(conn, path, report), 201) == %{"id" => id}
      # The client lost the response and sends the report again.
      assert json_response(post(conn, path, report), 201) == %{"id" => id}

      assert [_one] = ClickHouseRepo.all(from(b in Build, where: b.id == ^id))
      assert %{total: 1} = Tuist.Mix.compiled_files_page(%{id: id, project_id: project.id})
    end
  end

  test "refuses values the storage columns would wrap or that overflow later arithmetic", %{
    conn: conn,
    user: user,
    project: project
  } do
    path = "/api/projects/#{user.account.name}/#{project.name}/mix/builds"

    for report <- [
          %{files: [%{path: "lib/a.ex", compile_duration_ms: 4_294_967_296}]},
          %{steps: [%{category: "write", title: "Writing", start_offset_ms: 0, duration_ms: 4_294_967_296}]},
          %{
            machine_metrics: [
              %{timestamp: 1.0e308, cpu_usage_percent: 10.0, memory_used_bytes: 1, memory_total_bytes: 2}
            ]
          },
          %{
            machine_metrics: [
              %{
                timestamp: 1.0,
                cpu_usage_percent: 10.0,
                memory_used_bytes: 9_223_372_036_854_775_808,
                memory_total_bytes: 2
              }
            ]
          },
          %{files: [%{path: String.duplicate("a", 2_000), compile_duration_ms: 1}]},
          # Wider than any column, and enough to break the conversion to a float.
          %{
            machine_metrics: [
              %{timestamp: 1.0, cpu_usage_percent: Integer.pow(10, 400), memory_used_bytes: 1, memory_total_bytes: 2}
            ]
          }
        ] do
      response = post(conn, path, Map.merge(%{id: UUIDv7.generate(), duration_ms: 10, status: "success"}, report))
      assert response.status in [400, 422], "expected a client error for #{inspect(report)}, got #{response.status}"
    end

    assert ClickHouseRepo.all(from(b in Build, where: b.project_id == ^project.id)) == []
  end
end
