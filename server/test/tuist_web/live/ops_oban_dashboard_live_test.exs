defmodule TuistWeb.OpsObanDashboardLiveTest do
  # Oban Web needs Oban's globally registered metrics processes, which tests
  # do not start by default.
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Accounts
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup %{conn: conn} do
    start_supervised!(
      {Oban.Sonar, conf: %{Oban.config() | testing: :disabled}, name: Oban.Registry.via(Oban, Oban.Sonar)}
    )

    start_supervised!({Oban.Met, conf: Oban.config()})
    stub(Accounts, :tuist_operator?, fn _ -> true end)
    %{conn: log_in_user(conn, AccountsFixtures.user_fixture())}
  end

  test "a revoked browser session cannot cancel jobs from an open dashboard", %{conn: conn} do
    job = Repo.insert!(Oban.Job.new(%{}, worker: "Tuist.NoSuchWorker"))
    {:ok, view, _} = live(conn, "/ops/oban/jobs?state=available")
    view |> with_target("#jobs-page") |> render_hook("toggle-select-all", %{})
    assert has_element?(view, "#bulk-actions")

    conn |> get_session(:user_token) |> Accounts.delete_user_session_token()
    view |> with_target("#jobs-page") |> render_hook("cancel-jobs", %{})

    assert_redirect(view)
    assert Repo.get!(Oban.Job, job.id).state == "available"
  end

  test "a valid session can still cancel jobs", %{conn: conn} do
    job = Repo.insert!(Oban.Job.new(%{}, worker: "Tuist.NoSuchWorker"))
    {:ok, view, _} = live(conn, "/ops/oban/jobs?state=available")
    view |> with_target("#jobs-page") |> render_hook("toggle-select-all", %{})
    view |> with_target("#jobs-page") |> render_hook("cancel-jobs", %{})
    render(view)

    assert Repo.get!(Oban.Job, job.id).state == "cancelled"
  end
end
