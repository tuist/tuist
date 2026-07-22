defmodule TuistWeb.OpsKuraRolloutLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Accounts
  alias Tuist.Kura.Rollout
  alias Tuist.Kura.Rollouts
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])

    conn = log_in_user(conn, user)

    Mimic.stub(Accounts, :tuist_operator?, fn _ -> true end)
    Mimic.stub(Tuist.FeatureFlags, :kura_rollout_orchestration_enabled?, fn -> true end)
    Mimic.stub(Tuist.Kura.Rollouts.Notifier, :notify, fn _event, _rollout, _metadata -> :ok end)

    %{conn: conn, user: user}
  end

  defp create_rollout do
    {:ok, rollout} =
      %{image_tag: "0.6.0", baseline_image_tag: "0.5.2", mode: :progressive}
      |> Rollout.create_changeset()
      |> Repo.insert()

    rollout
  end

  test "renders the empty state when no rollout exists", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/ops/kura")

    assert html =~ "No rollout has been recorded yet"
  end

  test "renders the active rollout with its facts", %{conn: conn} do
    create_rollout()

    {:ok, _lv, html} = live(conn, ~p"/ops/kura")

    assert html =~ "Rollout 0.6.0"
    assert html =~ "running"
    assert html =~ "progressive"
    assert html =~ "0.5.2"
  end

  test "pauses the rollout through the operator controls", %{conn: conn} do
    rollout = create_rollout()

    {:ok, lv, _html} = live(conn, ~p"/ops/kura")

    lv
    |> form("form[phx-submit=operate]", %{
      reason: "observed suspicious latency",
      action: "pause"
    })
    |> render_submit()

    reloaded = Repo.get!(Rollout, rollout.id)
    assert reloaded.status == :paused

    [event | _] = Rollouts.list_events(reloaded)
    assert event.action == "paused"
    assert event.reason == "observed suspicious latency"
  end
end
