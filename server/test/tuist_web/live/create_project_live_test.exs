defmodule TuistWeb.CreateProjectLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase, async: true

  import Phoenix.LiveViewTest

  alias Tuist.Projects
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    %{account: account} =
      AccountsFixtures.organization_fixture(creator: user, preload: [:account])

    %{conn: log_in_user(conn, user), account: account}
  end

  for {build_system, label} <- [
        xcode: "Xcode",
        gradle: "Gradle",
        bazel: "Bazel",
        mix: "Mix (Elixir)",
        cargo: "Cargo (Rust)",
        once: "Once"
      ] do
    @build_system build_system
    @label label

    test "offers and creates a #{build_system} project", %{conn: conn, account: account} do
      {:ok, view, _html} = live(conn, ~p"/projects/new?account_id=#{account.id}")

      assert has_element?(view, "#build-system-selection option[value=#{@build_system}]", @label)
      assert has_element?(view, "#build-system-selection option[value=xcode][selected]")

      render_hook(view, "select_build_system", %{"value" => [to_string(@build_system)]})

      view
      |> form("#create-project-form", project: %{name: "my-project"})
      |> render_submit()

      project = Projects.get_project_by_account_and_project_handles(account.name, "my-project")

      assert project.build_system == @build_system
      assert_redirect(view, ~p"/#{account.name}/#{project.name}/connect")
    end
  end
end
