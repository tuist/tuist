defmodule Tuist.Kura.PodMetricsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Kura.PodMetrics
  alias Tuist.Kura.Server
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    user = AccountsFixtures.user_fixture()
    account = Accounts.get_account_from_user(user)

    {:ok, server} =
      %Server{}
      |> Server.create_changeset(%{
        account_id: account.id,
        region: "us-east",
        provisioner_node_ref: "kura-acme-us-east-1"
      })
      |> Repo.insert()

    %{server: server}
  end

  test "reads the pod through its headless service" do
    expect(Req, :get, fn url, _opts ->
      assert url ==
               "http://kura-acme-us-east-1-1.kura-acme-us-east-1-headless.kura.svc.cluster.local:4000/metrics"

      {:ok, %Req.Response{status: 200, body: "kura_http_requests_total 1\n"}}
    end)

    assert {:ok, "kura_http_requests_total 1\n"} = PodMetrics.fetch("kura-acme-us-east-1-1")
  end

  test "reads a multi-digit ordinal rather than folding it into the ref" do
    expect(Req, :get, fn url, _opts ->
      assert url =~ "http://kura-acme-us-east-1-12.kura-acme-us-east-1-headless."
      {:ok, %Req.Response{status: 200, body: ""}}
    end)

    assert {:ok, ""} = PodMetrics.fetch("kura-acme-us-east-1-12")
  end

  test "rejects a name that cannot be a statefulset pod" do
    reject(&Req.get/2)

    assert {:error, :invalid_pod_name} = PodMetrics.fetch("kura-acme-us-east")
    assert {:error, :invalid_pod_name} = PodMetrics.fetch("../../secrets-0")
    assert {:error, :invalid_pod_name} = PodMetrics.fetch("evil.example.com-0")
    assert {:error, :invalid_pod_name} = PodMetrics.fetch("kura-acme-us-east-1-1:9090/x")
  end

  test "refuses a ref that no server owns" do
    reject(&Req.get/2)

    assert {:error, :not_found} = PodMetrics.fetch("kura-other-us-east-1-0")
  end

  test "refuses an instance name, whose trailing segment is not an ordinal" do
    reject(&Req.get/2)

    assert {:error, :not_found} = PodMetrics.fetch("kura-acme-us-east-1")
  end

  test "reads the live server when a destroyed one kept the same ref", %{server: server} do
    {:ok, destroyed} =
      server
      |> Server.status_changeset(%{status: :destroying})
      |> Repo.update()

    {:ok, _} = destroyed |> Server.status_changeset(%{status: :destroyed}) |> Repo.update()

    user = AccountsFixtures.user_fixture()

    {:ok, _recreated} =
      %Server{}
      |> Server.create_changeset(%{
        account_id: Accounts.get_account_from_user(user).id,
        region: "us-east",
        provisioner_node_ref: "kura-acme-us-east-1"
      })
      |> Repo.insert()

    expect(Req, :get, fn _url, _opts -> {:ok, %Req.Response{status: 200, body: "ok\n"}} end)

    assert {:ok, "ok\n"} = PodMetrics.fetch("kura-acme-us-east-1-0")
  end

  test "reports an unreachable pod" do
    expect(Req, :get, fn _url, _opts -> {:error, %Mint.TransportError{reason: :timeout}} end)

    assert {:error, {:unreachable, _}} = PodMetrics.fetch("kura-acme-us-east-1-0")
  end

  test "reports an unexpected status" do
    expect(Req, :get, fn _url, _opts -> {:ok, %Req.Response{status: 503, body: ""}} end)

    assert {:error, {:unexpected_status, 503}} = PodMetrics.fetch("kura-acme-us-east-1-0")
  end
end
