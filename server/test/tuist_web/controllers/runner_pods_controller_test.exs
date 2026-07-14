defmodule TuistWeb.RunnerPodsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import Ecto.Query
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Repo
  alias Tuist.Runners.InteractiveSessions
  alias Tuist.Runners.RunnerSession

  defp session_fixture(account, attrs) do
    defaults = %{
      account_id: account.id,
      workflow_job_id: System.unique_integer([:positive]),
      fleet_name: "fleet-podctrl",
      pod_name: "pod-#{System.unique_integer([:positive])}",
      runner_name: "",
      started_at: DateTime.utc_now(),
      ended_at: nil,
      inserted_at: DateTime.truncate(DateTime.utc_now(), :second),
      updated_at: DateTime.truncate(DateTime.utc_now(), :second)
    }

    Repo.insert!(struct(RunnerSession, Map.merge(defaults, Map.new(attrs))))
  end

  defp ok_tokenreview_stub do
    stub(K8sClient, :create_controller_token_review, fn "valid-token" ->
      {:ok, %{namespace: "tuist", name: "tuist-runners-controller"}}
    end)
  end

  describe "POST /api/internal/runners/pods/stopped" do
    test "closes the matching open sessions and returns 204", %{conn: conn} do
      account = account_fixture()
      user = user_fixture()
      pod_name = "tuist-macos-runner-pod-1"
      started_at = ~U[2026-05-26 12:00:00.000000Z]
      ended_at = ~U[2026-05-26 12:05:00.000000Z]

      session_fixture(account, pod_name: pod_name, started_at: started_at)

      {:ok, interactive_session} =
        InteractiveSessions.request_vnc(
          %{
            account_id: account.id,
            workflow_job_id: 99_001,
            fleet_name: "macos-xcode-26-5",
            status: "running",
            pod_name: pod_name
          },
          account,
          user
        )

      ok_tokenreview_stub()

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post("/api/internal/runners/pods/stopped", %{
          "pod_name" => pod_name,
          "ended_at" => DateTime.to_iso8601(ended_at)
        })

      assert response(conn, 204)

      [session] = Repo.all(from(s in RunnerSession, where: s.pod_name == ^pod_name))
      assert DateTime.compare(session.ended_at, ended_at) == :eq
      assert Repo.reload!(interactive_session).state == :closed
    end

    test "returns 204 when no open session matches (idempotent / out-of-order delivery)", %{conn: conn} do
      ok_tokenreview_stub()

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post("/api/internal/runners/pods/stopped", %{
          "pod_name" => "ghost-pod",
          "ended_at" => DateTime.to_iso8601(~U[2026-05-26 13:00:00.000000Z])
        })

      assert response(conn, 204)
    end

    test "returns 400 when pod_name is missing", %{conn: conn} do
      ok_tokenreview_stub()

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post("/api/internal/runners/pods/stopped", %{
          "ended_at" => DateTime.to_iso8601(DateTime.utc_now())
        })

      assert json_response(conn, 400)["error"] =~ "pod_name"
    end

    test "returns 400 when ended_at is missing", %{conn: conn} do
      ok_tokenreview_stub()

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post("/api/internal/runners/pods/stopped", %{"pod_name" => "pod-x"})

      assert json_response(conn, 400)["error"] =~ "ended_at"
    end

    test "returns 400 when ended_at isn't ISO-8601", %{conn: conn} do
      ok_tokenreview_stub()

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post("/api/internal/runners/pods/stopped", %{
          "pod_name" => "pod-x",
          "ended_at" => "yesterday"
        })

      assert json_response(conn, 400)["error"] =~ "invalid"
    end

    test "returns 401 when bearer token is missing", %{conn: conn} do
      conn = post(conn, "/api/internal/runners/pods/stopped", %{"pod_name" => "pod-x"})
      assert json_response(conn, 401)["error"] =~ "bearer"
    end

    test "returns 401 when TokenReview rejects the token", %{conn: conn} do
      stub(K8sClient, :create_controller_token_review, fn _ -> {:error, :unauthenticated} end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer bad-token")
        |> post("/api/internal/runners/pods/stopped", %{
          "pod_name" => "pod-x",
          "ended_at" => DateTime.to_iso8601(DateTime.utc_now())
        })

      assert json_response(conn, 401)["error"] =~ "invalid"
    end

    test "returns 401 when the principal isn't the runners-controller SA", %{conn: conn} do
      # Any in-cluster workload could present a valid SA token, but
      # only the runners-controller is allowed to close billing
      # sessions. Tokens from any other SA must be rejected.
      stub(K8sClient, :create_controller_token_review, fn _ ->
        {:ok, %{namespace: "other-ns", name: "other-sa"}}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer foreign-token")
        |> post("/api/internal/runners/pods/stopped", %{
          "pod_name" => "pod-x",
          "ended_at" => DateTime.to_iso8601(DateTime.utc_now())
        })

      assert json_response(conn, 401)["error"] =~ "unauthorized"
    end

    test "returns 503 when kubernetes is unavailable", %{conn: conn} do
      stub(K8sClient, :create_controller_token_review, fn _ -> {:error, :not_in_cluster} end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer any-token")
        |> post("/api/internal/runners/pods/stopped", %{
          "pod_name" => "pod-x",
          "ended_at" => DateTime.to_iso8601(DateTime.utc_now())
        })

      assert json_response(conn, 503)["error"] =~ "kubernetes"
    end
  end
end
