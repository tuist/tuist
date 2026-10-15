defmodule TuistWeb.OriginAppControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.Origin.Auth
  alias Tuist.Origin.Client
  alias Tuist.Origin.Installation
  alias Tuist.Origin.RunnerCheckout
  alias Tuist.Repo
  alias Tuist.Runners.Buildkite.Job
  alias Tuist.Runners.Buildkite.ReportToken
  alias Tuist.Runners.WorkflowJob
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup %{conn: conn} do
    user = Repo.preload(AccountsFixtures.user_fixture(), :account)
    stub(Environment, :origin_app_credentials, fn -> %{app_id: "app-tuist"} end)
    claims = %{"sub" => "inst-#{user.id}", "namespace_id" => "ns-#{user.id}", "exp" => System.system_time(:second) + 300}
    stub(Auth, :verify_receipt, fn "signed" -> {:ok, claims} end)

    stub(Client, :get_installation, fn _ ->
      {:ok,
       %{"id" => claims["sub"], "appId" => "app-tuist", "target" => %{"id" => claims["namespace_id"], "slug" => "org"}}}
    end)

    %{conn: conn, user: user, claims: claims}
  end

  test "marketplace approval strips the receipt, survives sign-in and requires explicit authorized confirmation", %{
    conn: conn,
    user: user
  } do
    callback = get(conn, "/integrations/origin/setup?installation_receipt=signed")
    assert redirected_to(callback) == "/integrations/origin/continue"
    pending = get_session(callback, :pending_origin)
    assert pending["installation_id"] == "inst-#{user.id}"
    refute Repo.get_by(Installation, account_id: user.account.id)

    login =
      callback
      |> recycle()
      |> post("/users/log_in", %{
        "user" => %{"email" => user.email, "password" => AccountsFixtures.valid_user_password()}
      })

    assert get_session(login, :pending_origin) == pending
    confirmed = login |> recycle() |> post("/integrations/origin/connect", %{account_id: user.account.id})
    assert redirected_to(confirmed) == "/#{user.account.name}/settings/integrations"
    assert Repo.get_by(Installation, account_id: user.account.id).installation_id == pending["installation_id"]
    refute get_session(confirmed, :pending_origin)
  end

  test "initiated installs reject a different nonce and do not retain pending approval", %{conn: conn, claims: claims} do
    stub(Auth, :verify_receipt, fn _ -> {:ok, Map.put(claims, "state", "wrong")} end)

    conn =
      conn
      |> init_test_session(origin_install_state: %{"nonce" => "expected"})
      |> get("/integrations/origin/setup?installation_receipt=signed")

    assert response(conn, 400)
    refute get_session(conn, :pending_origin)
  end

  test "an account ID cannot attach an installation to an unrelated account", %{conn: conn, user: user} do
    other = Repo.preload(AccountsFixtures.user_fixture(), :account)
    approved = conn |> log_in_user(user) |> get("/integrations/origin/setup?installation_receipt=signed")
    rejected = approved |> recycle() |> post("/integrations/origin/connect", %{account_id: other.account.id})
    assert response(rejected, 403)
    refute Repo.get_by(Installation, account_id: other.account.id)
  end

  describe "runner checkout" do
    setup %{user: user, claims: claims} do
      installation =
        Repo.insert!(
          Installation.changeset(%Installation{}, %{
            account_id: user.account.id,
            installation_id: claims["sub"],
            namespace_id: claims["namespace_id"],
            namespace_slug: "org"
          })
        )

      job =
        Repo.insert!(
          Job.changeset(%Job{}, %{
            job_uuid: Ecto.UUID.generate(),
            account_id: user.account.id,
            organization_slug: "acme"
          }),
          returning: true
        )

      lifecycle =
        Repo.insert!(%WorkflowJob{
          workflow_job_id: job.workflow_job_id,
          account_id: user.account.id,
          provider: "buildkite",
          status: "claimed",
          fleet_name: "linux-amd64",
          enqueued_at: DateTime.utc_now()
        })

      remote = "https://origin.cursor.com/org/repo.git"

      payload = %{
        "id" => job.job_uuid,
        "env" => %{
          "BUILDKITE_JOB_ID" => job.job_uuid,
          "BUILDKITE_ORGANIZATION_SLUG" => "acme",
          "BUILDKITE_REPO" => remote
        }
      }

      stub(Client, :repositories, fn _ -> {:ok, [%{"id" => "repo-1", "fullName" => "org/repo"}]} end)
      stub(Auth, :app_jwt, fn -> {:ok, "signed-app-jwt"} end)

      stub(Req, :request, fn opts ->
        assert opts[:json] == %{scopes: ["repository:contents:read"], repositoryIds: ["repo-1"]}
        assert opts[:url] == "https://api.cursor.com/v1/origin/app/installations/#{claims["sub"]}/access_tokens"
        {:ok, %{status: 200, body: %{"token" => "oit_#{System.unique_integer([:positive])}"}}}
      end)

      assert {:ok, grant} = RunnerCheckout.grant(job, payload)
      %{grant: grant, remote: remote, job: job, payload: payload, installation: installation, lifecycle: lifecycle}
    end

    test "refreshes one read-only repository credential without accepting report tokens or other remotes", context do
      %{conn: conn, grant: grant, remote: remote, job: job, payload: payload} = context
      first = checkout(conn, grant, remote)
      first_token = json_response(first, 200)["token"]
      assert get_resp_header(first, "cache-control") == ["no-store"]
      refute json_response(checkout(conn, grant, remote), 200)["token"] == first_token

      for wrong_remote <- ["https://origin.cursor.com/org/other.git", "https://github.com/org/repo.git"] do
        assert response(checkout(conn, grant, wrong_remote), 403)
      end

      report = ReportToken.mint(%{workflow_job_id: job.workflow_job_id, account_id: job.account_id})
      assert response(checkout(conn, report, remote), 403)
      assert response(checkout(conn, grant <> "tampered", remote), 403)

      assert {:ok, nil} =
               RunnerCheckout.grant(job, put_in(payload, ["env", "BUILDKITE_REPO"], "git@github.com:org/repo.git"))

      assert {:ok, nil} = RunnerCheckout.grant(job, Map.put(payload, "id", "another-job"))

      other = Repo.preload(AccountsFixtures.user_fixture(), :account)

      assert {:error, :origin_repository_not_accessible} =
               RunnerCheckout.grant(%{job | account_id: other.account.id}, payload)

      Repo.update!(Ecto.Changeset.change(job, account_id: other.account.id))
      assert response(checkout(conn, grant, remote), 403)
    end

    test "denies terminal jobs, suspension and revoked repository access, and returns retryable outages", context do
      %{conn: conn, grant: grant, remote: remote, installation: installation, lifecycle: lifecycle} = context
      Repo.update!(Ecto.Changeset.change(lifecycle, status: "completed"))
      assert response(checkout(conn, grant, remote), 403)
      Repo.update!(Ecto.Changeset.change(lifecycle, status: "running"))
      assert json_response(checkout(conn, grant, remote), 200)["token"] =~ "oit_"

      suspended = Repo.update!(Ecto.Changeset.change(installation, suspended: true))
      assert response(checkout(conn, grant, remote), 403)
      Repo.update!(Ecto.Changeset.change(suspended, suspended: false))
      stub(Req, :request, fn _ -> {:ok, %{status: 503}} end)
      assert response(checkout(conn, grant, remote), 503)

      stub(Client, :repositories, fn _ -> {:ok, []} end)
      assert response(checkout(conn, grant, remote), 403)
      stub(Client, :repositories, fn _ -> {:ok, [%{"id" => "repo-1", "mirror" => %{}}]} end)
      assert response(checkout(conn, grant, remote), 403)
      Repo.delete!(installation)
      assert response(checkout(conn, grant, remote), 403)
    end
  end

  defp checkout(conn, grant, remote) do
    conn
    |> put_req_header("authorization", "Bearer " <> grant)
    |> post("/api/internal/runners/jobs/origin-credentials", %{repo_url: remote})
  end
end
