defmodule TuistWeb.OpsKuraRolloutsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Accounts
  alias Tuist.Kura.Rollout
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])

    conn = log_in_user(conn, user)

    Mimic.stub(Accounts, :tuist_operator?, fn _ -> true end)

    %{conn: conn, user: user}
  end

  defp create_completed_rollouts(count) do
    for index <- 1..count do
      {:ok, rollout} =
        %{image_tag: "0.6.#{index}", mode: :expedited}
        |> Rollout.create_changeset()
        |> Repo.insert()

      {:ok, rollout} =
        rollout
        |> Rollout.update_changeset(%{
          status: :completed,
          completed_at: DateTime.truncate(DateTime.utc_now(), :second)
        })
        |> Repo.update()

      rollout
    end
  end

  test "paginates the rollout history newest first", %{conn: conn} do
    create_completed_rollouts(30)

    {:ok, _lv, html} = live(conn, ~p"/ops/kura/rollouts")
    # 30 rollouts at 25 per page: the newest ones are on page one.
    assert html =~ "0.6.30"
    refute html =~ ">0.6.1<"

    {:ok, _lv, html} = live(conn, ~p"/ops/kura/rollouts?page=2")
    assert html =~ "0.6.1"
    refute html =~ "0.6.30"
  end

  test "rows link to the rollout detail page", %{conn: conn} do
    [rollout | _] = create_completed_rollouts(1)

    {:ok, _lv, html} = live(conn, ~p"/ops/kura/rollouts")

    assert html =~ ~p"/ops/kura/rollouts/#{rollout.id}"
  end
end
