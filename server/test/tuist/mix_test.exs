defmodule Tuist.MixTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Mix
  alias Tuist.Mix.Build
  alias Tuist.Mix.Diagnostic
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  describe "create_build/1" do
    setup do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)
      %{user: user, project: project}
    end

    test "accepts a start time without fractional seconds", %{user: user, project: project} do
      id = UUIDv7.generate()

      assert {:ok, ^id} =
               Mix.create_build(%{
                 id: id,
                 project_id: project.id,
                 account_id: user.account.id,
                 duration_ms: 10,
                 status: "success",
                 started_at: "2026-09-09T10:00:00Z"
               })

      assert {:ok, %{started_at: ~N[2026-09-09 10:00:00.000000]}} = Mix.get_build(id)
    end

    test "stores a report that arrives twice at once only once", %{user: user, project: project} do
      id = UUIDv7.generate()

      attrs = %{
        id: id,
        project_id: project.id,
        account_id: user.account.id,
        duration_ms: 10,
        status: "success",
        diagnostics: [%{severity: "warning", file: "lib/a.ex", message: "unused"}]
      }

      results = [attrs, attrs] |> Enum.map(&Task.async(fn -> Mix.create_build(&1) end)) |> Task.await_many()

      assert results == [{:ok, id}, {:ok, id}]

      assert ClickHouseRepo.one(from(b in Build, where: b.id == ^id, select: count())) == 1
      assert ClickHouseRepo.one(from(d in Diagnostic, where: d.build_id == ^id, select: count())) == 1
    end

    test "persists the build row and each diagnostic", %{user: user, project: project} do
      attrs = %{
        id: UUIDv7.generate(),
        project_id: project.id,
        account_id: user.account.id,
        duration_ms: 123,
        status: "success",
        is_ci: true,
        elixir_version: "1.20.2",
        otp_version: "29",
        mix_env: "dev",
        git_branch: "main",
        contract_version: "0.1",
        diagnostics: [
          %{
            severity: "warning",
            file: "lib/a.ex",
            module: "A",
            message: "unused variable",
            line: 4,
            column: 2,
            compiler: "elixir"
          },
          %{
            severity: "error",
            file: "lib/b.ex",
            module: "B",
            message: "undefined function",
            line: 12,
            compiler: "app"
          }
        ]
      }

      assert {:ok, build_id} = Mix.create_build(attrs)
      assert build_id == attrs.id

      assert [build] = ClickHouseRepo.all(from(b in Build, where: b.id == ^build_id))
      assert build.status == "success"
      assert build.elixir_version == "1.20.2"
      assert build.contract_version == "0.1"
      assert build.diagnostics_error_count == 1
      assert build.diagnostics_warning_count == 1

      diagnostics =
        ClickHouseRepo.all(from(d in Diagnostic, where: d.build_id == ^build_id, order_by: [asc: d.severity]))

      assert length(diagnostics) == 2
      assert Enum.map(diagnostics, & &1.severity) == ["warning", "error"]
    end

    test "persists the per-file profile and derives which files block others", %{user: user, project: project} do
      build_id = UUIDv7.generate()

      {:ok, ^build_id} =
        Mix.create_build(%{
          id: build_id,
          project_id: project.id,
          account_id: user.account.id,
          duration_ms: 500,
          status: "success",
          files: [
            %{path: "lib/macros.ex", compile_duration_ms: 300, modules: ["Demo.Macros"]},
            %{
              path: "lib/greeter.ex",
              compile_duration_ms: 70,
              modules: ["Demo.Greeter"],
              dependencies: [
                %{path: "lib/macros.ex", kind: "compile"},
                %{path: "lib/user.ex", kind: "export"},
                %{path: "lib/other.ex", kind: "runtime"}
              ]
            },
            %{
              path: "lib/other.ex",
              compile_duration_ms: 10,
              modules: ["Demo.Other"],
              dependencies: [%{path: "lib/macros.ex", kind: "compile"}, %{path: "lib/greeter.ex", kind: "unknown"}]
            }
          ]
        })

      Mix.CompiledFile.Buffer.flush()

      build = %{id: build_id, project_id: project.id}

      # By name, to tell the three apart.
      assert %{total: 3, rows: [greeter, macros, other]} = Mix.compiled_files_page(build, sort_by: "name")
      assert Enum.map([greeter, macros, other], & &1.name) == ["lib/greeter.ex", "lib/macros.ex", "lib/other.ex"]

      # Compile and export dependencies order compilation; runtime ones do not,
      # and an unrecognised kind is stored as the weakest one.
      assert greeter.compile_dependencies_count == 2
      assert other.compile_dependencies_count == 1
      assert macros.compile_dependencies_count == 0
      assert macros.compile_dependents_count == 2
      assert other.compile_dependents_count == 0
      assert greeter.compile_dependents_count == 0

      # Sorting, searching and paging happen in the database.
      assert %{rows: [%{name: "lib/macros.ex"} | _]} = Mix.compiled_files_page(build, sort_by: "dependents")
      assert %{rows: [%{name: "lib/greeter.ex"} | _]} = Mix.compiled_files_page(build, sort_by: "dependencies")
      assert %{rows: [%{name: "lib/macros.ex", compile_duration_ms: 300} | _]} = Mix.compiled_files_page(build)
      assert %{total: 1, rows: [%{name: "lib/greeter.ex"}]} = Mix.compiled_files_page(build, search: "GREET")

      assert %{total: 3, rows: [%{name: "lib/other.ex"}]} =
               Mix.compiled_files_page(build, sort_by: "name", page: 3, page_size: 1)

      assert %{total: 3, rows: []} = Mix.compiled_files_page(build, page: 2)

      # One row per module, carrying its file's numbers.
      assert %{total: 3, rows: [%{name: "Demo.Greeter", path: "lib/greeter.ex", compile_dependencies_count: 2} | _]} =
               Mix.compiled_files_page(build, by: :module, sort_by: "name")

      assert %{total: 1} = Mix.compiled_files_page(build, by: :module, search: "macros")

      # Another project asking for the same id sees nothing.
      assert %{total: 0, rows: []} = Mix.compiled_files_page(%{build | project_id: project.id + 1})
      refute Mix.compiled_files?(%{build | project_id: project.id + 1})
      assert Mix.compiled_files?(build)
    end

    test "rejects invalid custom metadata", %{user: user, project: project} do
      attrs = %{
        id: UUIDv7.generate(),
        project_id: project.id,
        account_id: user.account.id,
        duration_ms: 10,
        status: "success",
        custom_tags: List.duplicate("tag", 200)
      }

      assert {:error, _reason} = Mix.create_build(attrs)
    end
  end
end
