defmodule TuistWeb.KuraRolloutStatusControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Kura.Rollout
  alias Tuist.Repo

  describe "GET /api/kura/rollout-status" do
    test "reports the machinery disabled when the flag is off", %{conn: conn} do
      stub(Tuist.FeatureFlags, :kura_rollout_orchestration_enabled?, fn -> false end)

      conn = get(conn, "/api/kura/rollout-status", %{"image_tag" => "0.6.0"})

      assert json_response(conn, 200) == %{"enabled" => false, "rollout" => nil}
    end

    test "returns no rollout when none exists for the tag", %{conn: conn} do
      stub(Tuist.FeatureFlags, :kura_rollout_orchestration_enabled?, fn -> true end)

      conn = get(conn, "/api/kura/rollout-status", %{"image_tag" => "0.6.0"})

      assert json_response(conn, 200) == %{"enabled" => true, "rollout" => nil}
    end

    test "returns the latest rollout for the tag", %{conn: conn} do
      stub(Tuist.FeatureFlags, :kura_rollout_orchestration_enabled?, fn -> true end)

      {:ok, rollout} =
        %{image_tag: "0.6.0", mode: :expedited}
        |> Rollout.create_changeset()
        |> Repo.insert()

      {:ok, _} =
        rollout
        |> Rollout.update_changeset(%{status: :completed, completed_at: DateTime.truncate(DateTime.utc_now(), :second)})
        |> Repo.update()

      conn = get(conn, "/api/kura/rollout-status", %{"image_tag" => "0.6.0"})

      assert %{
               "enabled" => true,
               "rollout" => %{
                 "image_tag" => "0.6.0",
                 "status" => "completed",
                 "mode" => "expedited",
                 "current_wave" => 0
               }
             } = json_response(conn, 200)
    end

    test "requires an image_tag", %{conn: conn} do
      conn = get(conn, "/api/kura/rollout-status")

      assert json_response(conn, 400) == %{"error" => "image_tag is required"}
    end
  end
end
