defmodule Tuist.MixTest do
  use TuistTestSupport.Cases.DataCase, async: false

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
