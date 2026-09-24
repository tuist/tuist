defmodule TuistWeb.OpsKuraRolloutLiveTest do
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
  alias TuistWeb.Errors.NotFoundError

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])

    conn = log_in_user(conn, user)

    Mimic.stub(Accounts, :tuist_operator?, fn _ -> true end)
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

  defp complete(rollout) do
    {:ok, rollout} =
      rollout
      |> Rollout.update_changeset(%{
        status: :completed,
        completed_at: DateTime.truncate(DateTime.utc_now(), :second)
      })
      |> Repo.update()

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

  test "renders a terminal rollout's facts and trail", %{conn: conn} do
    rollout = create_rollout()
    record_events(rollout, 3)
    rollout = complete(rollout)

    {:ok, _lv, html} = live(conn, ~p"/ops/kura/rollouts/#{rollout.id}")

    assert html =~ "Rollout 0.6.0"
    assert html =~ "completed"
    assert html =~ "wave_completed"
    # Terminal rollouts render no operator controls.
    refute html =~ "phx-submit=\"operate\""
  end

  test "renders the servers a paused StatefulSet holds", %{conn: conn} do
    {:ok, rollout} =
      create_rollout()
      |> Rollout.update_changeset(%{
        status: :paused,
        paused_at: DateTime.truncate(DateTime.utc_now(), :second),
        pause_reason: "statefulset_update_paused"
      })
      |> Repo.update()

    {:ok, _} =
      %{
        kura_rollout_id: rollout.id,
        action: "paused",
        actor: "gate",
        metadata: %{
          wave: 1,
          signal: :statefulset_update_paused,
          servers: [
            %{
              server_id: "server-a",
              region: "eu-east",
              strategy: "updateStrategy OnDelete",
              held_pods: ["kura-a-0", "kura-a-1"]
            }
          ]
        }
      }
      |> RolloutEvent.create_changeset()
      |> Repo.insert()

    {:ok, _lv, html} = live(conn, ~p"/ops/kura/rollouts/#{rollout.id}")

    assert html =~ "statefulset_update_paused"
    assert html =~ "strategy=updateStrategy OnDelete"
    assert html =~ "held_pods=kura-a-0,kura-a-1"
    assert html =~ "server_id=server-a"
  end

  test "paginates the audit trail", %{conn: conn} do
    rollout = create_rollout()
    record_events(rollout, 30)

    {:ok, _lv, html} = live(conn, ~p"/ops/kura/rollouts/#{rollout.id}")
    assert html =~ "wave: 30"
    refute html =~ "wave: 1<"

    {:ok, _lv, html} = live(conn, ~p"/ops/kura/rollouts/#{rollout.id}?page=2")
    assert html =~ "wave: 1"
    refute html =~ "wave: 30"
  end

  test "operates on a non-terminal rollout from the detail page", %{conn: conn} do
    rollout = create_rollout()

    {:ok, lv, _html} = live(conn, ~p"/ops/kura/rollouts/#{rollout.id}")

    lv
    |> form("form[phx-submit=operate]", %{reason: "detail page drill", action: "pause"})
    |> render_submit()

    reloaded = Repo.get!(Rollout, rollout.id)
    assert reloaded.status == :paused

    [event | _] = Rollouts.list_events(reloaded)
    assert event.action == "paused"
  end

  test "raises not found for an unknown rollout", %{conn: conn} do
    assert_raise NotFoundError, fn ->
      live(conn, ~p"/ops/kura/rollouts/#{Ecto.UUID.generate()}")
    end
  end

  test "raises not found rather than a cast error for a malformed id", %{conn: conn} do
    assert_raise NotFoundError, fn ->
      live(conn, ~p"/ops/kura/rollouts/not-a-uuid")
    end
  end
end
