defmodule TuistWeb.OpsKuraLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Accounts
  alias Tuist.Kura.Rollout
  alias Tuist.Kura.RolloutEvent
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

  defp create_rollout(attrs \\ %{}) do
    {:ok, rollout} =
      %{image_tag: "0.6.0", baseline_image_tag: "0.5.2", mode: :progressive}
      |> Map.merge(attrs)
      |> Rollout.create_changeset()
      |> Repo.insert()

    rollout
  end

  defp record_events(rollout, count) do
    for index <- 1..count do
      {:ok, _} =
        %{
          kura_rollout_id: rollout.id,
          action: "wave_completed",
          actor: "system",
          metadata: %{wave: index}
        }
        |> RolloutEvent.create_changeset()
        |> Repo.insert()
    end
  end

  test "renders the empty state when no rollout exists", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/ops/kura")

    assert html =~ "No rollout has been recorded yet"
  end

  test "renders the latest rollout with its facts", %{conn: conn} do
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

  test "leaving the action dropdown unselected operates on nothing", %{conn: conn} do
    rollout = create_rollout()

    {:ok, lv, _html} = live(conn, ~p"/ops/kura")

    lv
    |> form("form[phx-submit=operate]", %{reason: "no action picked", action: ""})
    |> render_submit()

    assert Repo.get!(Rollout, rollout.id).status == :running
    assert Rollouts.list_events(rollout) == []

    assert TuistWeb.OpsKuraComponents.operate_error_message(:no_action_selected, "") ==
             "Choose an action to apply."
  end

  test "links to the rollout detail page for the audit trail", %{conn: conn} do
    rollout = create_rollout()
    record_events(rollout, 12)

    {:ok, _lv, html} = live(conn, ~p"/ops/kura")

    # The overview carries no event table; the trail lives on the detail page.
    assert html =~ "View details"
    assert html =~ ~p"/ops/kura/rollouts/#{rollout.id}"
    refute html =~ "wave_completed"
  end

  test "links to the paginated rollout history when there are more rollouts", %{conn: conn} do
    for index <- 1..11 do
      {:ok, rollout} =
        %{image_tag: "0.6.#{index}", mode: :expedited}
        |> Rollout.create_changeset()
        |> Repo.insert()

      {:ok, _} =
        rollout
        |> Rollout.update_changeset(%{
          status: :completed,
          completed_at: DateTime.truncate(DateTime.utc_now(), :second)
        })
        |> Repo.update()
    end

    {:ok, _lv, html} = live(conn, ~p"/ops/kura")

    assert html =~ "View all"
    assert html =~ ~p"/ops/kura/rollouts"
  end
end
