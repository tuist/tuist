defmodule Tuist.Kura.ReconcilerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Kura
  alias Tuist.Kura.Deployment
  alias Tuist.Kura.Provisioner
  alias Tuist.Kura.Reconciler
  alias Tuist.Kura.Server
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :set_mimic_from_context

  setup do
    stub(Tuist.Environment, :kura_runtime_image_tag, fn -> nil end)
    stub(Provisioner, :public_url, fn _account, _server -> "http://localhost:4100" end)
    :ok
  end

  test "applies a pending deployment when the KuraInstance is missing" do
    {_account, server, deployment} = create_server()

    expect(Provisioner, :current_image_tag, fn %Server{id: id} ->
      assert id == server.id
      {:error, :not_found}
    end)

    expect(Provisioner, :rollout, fn %Server{id: id}, inputs ->
      assert id == server.id
      assert inputs.image_tag == deployment.image_tag
      :ok
    end)

    assert :ok = Reconciler.reconcile()

    assert %Deployment{status: :running} = Repo.get!(Deployment, deployment.id)
    assert %Server{status: :provisioning, current_image_tag: nil} = Repo.get!(Server, server.id)
  end

  test "marks a deployment succeeded when the controller observes the requested image" do
    {_account, server, deployment} = create_server()
    {:ok, deployment} = Kura.mark_running(deployment)

    expect(Provisioner, :current_image_tag, fn %Server{id: id} ->
      assert id == server.id
      {:ok, deployment.image_tag}
    end)

    assert :ok = Reconciler.reconcile()

    assert %Deployment{status: :succeeded, error_message: nil} = Repo.get!(Deployment, deployment.id)

    assert %Server{status: :active, current_image_tag: "0.5.2", url: "http://localhost:4100"} =
             Repo.get!(Server, server.id)
  end

  test "marks a pending deployment running before succeeding when the requested image is already observed" do
    {_account, server, deployment} = create_server()

    expect(Provisioner, :current_image_tag, fn %Server{id: id} ->
      assert id == server.id
      {:ok, deployment.image_tag}
    end)

    assert :ok = Reconciler.reconcile()

    assert %Deployment{status: :succeeded, error_message: nil} = Repo.get!(Deployment, deployment.id)

    assert %Server{status: :active, current_image_tag: "0.5.2", url: "http://localhost:4100"} =
             Repo.get!(Server, server.id)
  end

  test "keeps a deployment running until the public HTTPS endpoint is ready" do
    {account, server, deployment} = create_server()
    {:ok, deployment} = Kura.mark_running(deployment)

    expect(Provisioner, :current_image_tag, fn %Server{id: id} ->
      assert id == server.id
      {:ok, deployment.image_tag}
    end)

    expect(Provisioner, :public_url, fn account_arg, %Server{id: id} ->
      assert account_arg.id == account.id
      assert id == server.id
      "https://localhost:4100"
    end)

    expect(Req, :get, fn "https://localhost:4100/up", opts ->
      refute Keyword.has_key?(opts, :finch)
      assert opts[:receive_timeout] == 5_000
      assert opts[:connect_options] == [timeout: 5_000]
      assert opts[:retry] == false
      {:error, %Mint.TransportError{reason: {:tls_alert, ~c"unknown ca"}}}
    end)

    assert :ok = Reconciler.reconcile()

    assert %Deployment{status: :running} = Repo.get!(Deployment, deployment.id)
    assert %Server{status: :provisioning, current_image_tag: nil, url: nil} = Repo.get!(Server, server.id)
  end

  test "schedules and applies runtime image drift for active servers" do
    {_account, server, deployment} = create_server()
    {:ok, server} = Kura.activate_server(server, deployment.image_tag)
    mark_deployment_succeeded(deployment)

    stub(Tuist.Environment, :kura_runtime_image_tag, fn -> "sha-abcdef123456" end)

    expect(Provisioner, :current_image_tag, fn %Server{id: id} ->
      assert id == server.id
      {:ok, "0.5.2"}
    end)

    expect(Provisioner, :rollout, fn %Server{id: id}, inputs ->
      assert id == server.id
      assert inputs.image_tag == "sha-abcdef123456"
      :ok
    end)

    assert :ok = Reconciler.reconcile()

    assert %Deployment{status: :running} =
             Repo.get_by!(Deployment, kura_server_id: server.id, image_tag: "sha-abcdef123456")
  end

  test "marks destroying servers destroyed after the KuraInstance disappears" do
    {_account, server, deployment} = create_server()
    {:ok, server} = Kura.activate_server(server, deployment.image_tag)
    mark_deployment_succeeded(deployment)
    {:ok, server} = Kura.destroy_server(server)

    expect(Provisioner, :current_image_tag, fn %Server{id: id} ->
      assert id == server.id
      {:error, :not_found}
    end)

    assert :ok = Reconciler.reconcile()

    assert %Server{status: :destroyed} = Repo.get!(Server, server.id)
  end

  test "keeps destroying servers destroying while the KuraInstance still exists" do
    {_account, server, deployment} = create_server()
    {:ok, server} = Kura.activate_server(server, deployment.image_tag)
    mark_deployment_succeeded(deployment)
    {:ok, server} = Kura.destroy_server(server)

    expect(Provisioner, :current_image_tag, fn %Server{id: id} ->
      assert id == server.id
      {:ok, deployment.image_tag}
    end)

    expect(Provisioner, :destroy, fn %Server{id: id} ->
      assert id == server.id
      :ok
    end)

    assert :ok = Reconciler.reconcile()

    assert %Server{status: :destroying} = Repo.get!(Server, server.id)
  end

  test "marks a first-time-deploy server :failed and reports to Sentry when apply fails" do
    {_account, server, deployment} = create_server()

    expect(Provisioner, :current_image_tag, fn %Server{id: id} ->
      assert id == server.id
      {:error, :not_found}
    end)

    expect(Provisioner, :rollout, fn %Server{id: id}, _inputs ->
      assert id == server.id
      {:error, "apply failed"}
    end)

    expect(Sentry, :capture_message, fn "Kura deploy failed", opts ->
      assert opts[:level] == :error
      extra = opts[:extra]
      assert extra.deployment_id == deployment.id
      assert extra.server_id == server.id
      assert extra.region == server.region
      assert extra.reason == "apply failed"
      :ignored
    end)

    assert :ok = Reconciler.reconcile()

    assert %Deployment{status: :failed, error_message: "apply failed"} = Repo.get!(Deployment, deployment.id)
    assert %Server{status: :failed, current_image_tag: nil} = Repo.get!(Server, server.id)
  end

  test "marks a first-time-deploy server :failed and reports to Sentry when the cluster is unreachable" do
    {_account, server, deployment} = create_server()

    expect(Provisioner, :current_image_tag, fn %Server{id: id} ->
      assert id == server.id
      {:error, "missing Kubernetes kubeconfig for Kura cluster us-east-1"}
    end)

    expect(Sentry, :capture_message, fn "Kura deploy failed", opts ->
      assert opts[:level] == :error
      assert opts[:extra].reason == "missing Kubernetes kubeconfig for Kura cluster us-east-1"
      :ignored
    end)

    assert :ok = Reconciler.reconcile()

    assert %Deployment{
             status: :failed,
             error_message: "missing Kubernetes kubeconfig for Kura cluster us-east-1"
           } = Repo.get!(Deployment, deployment.id)

    assert %Server{status: :failed, current_image_tag: nil} = Repo.get!(Server, server.id)
  end

  test "keeps an active server at :failed when a drift rollout fails so the working endpoint stays up" do
    {_account, server, deployment} = create_server()
    {:ok, server} = Kura.activate_server(server, deployment.image_tag)
    mark_deployment_succeeded(deployment)

    stub(Tuist.Environment, :kura_runtime_image_tag, fn -> "sha-abcdef123456" end)

    expect(Provisioner, :current_image_tag, fn %Server{id: id} ->
      assert id == server.id
      {:ok, "0.5.2"}
    end)

    expect(Provisioner, :rollout, fn %Server{id: id}, _inputs ->
      assert id == server.id
      {:error, "apply failed"}
    end)

    expect(Sentry, :capture_message, fn "Kura deploy failed", _opts -> :ignored end)

    assert :ok = Reconciler.reconcile()

    drift_deployment = Repo.get_by!(Deployment, kura_server_id: server.id, image_tag: "sha-abcdef123456")
    assert drift_deployment.status == :failed
    assert %Server{status: :failed, url: url, current_image_tag: "0.5.2"} = Repo.get!(Server, server.id)
    assert is_binary(url)
  end

  test "heals a failed first-time-deploy server forward once the controller reports the target image" do
    {_account, server, deployment} = create_server()
    {:ok, _deployment} = Kura.mark_failed(deployment, "apply failed")
    {:ok, server} = Kura.fail_server(server)

    expect(Provisioner, :current_image_tag, fn %Server{id: id} ->
      assert id == server.id
      {:ok, deployment.image_tag}
    end)

    assert :ok = Reconciler.reconcile()

    assert %Server{status: :active, current_image_tag: "0.5.2", url: "http://localhost:4100"} =
             Repo.get!(Server, server.id)

    assert %Deployment{status: :failed} = Repo.get!(Deployment, deployment.id)
  end

  test "heals a previously-active failed server forward once the controller recovers" do
    {_account, server, deployment} = create_server()
    {:ok, server} = Kura.activate_server(server, deployment.image_tag)
    mark_deployment_succeeded(deployment)
    {:ok, server} = Kura.fail_server(server)

    expect(Provisioner, :current_image_tag, fn %Server{id: id} ->
      assert id == server.id
      {:ok, "0.5.2"}
    end)

    assert :ok = Reconciler.reconcile()

    assert %Server{status: :active, current_image_tag: "0.5.2"} = Repo.get!(Server, server.id)
  end

  test "leaves a failed server failed while the controller has not converged on the target image" do
    {_account, server, deployment} = create_server()
    {:ok, _deployment} = Kura.mark_failed(deployment, "apply failed")
    {:ok, server} = Kura.fail_server(server)

    expect(Provisioner, :current_image_tag, fn %Server{id: id} ->
      assert id == server.id
      {:error, :not_found}
    end)

    assert :ok = Reconciler.reconcile()

    assert %Server{status: :failed, current_image_tag: nil, url: nil} = Repo.get!(Server, server.id)
  end

  test "leaves a failed server failed while its public endpoint is not yet serving" do
    {account, server, deployment} = create_server()
    {:ok, _deployment} = Kura.mark_failed(deployment, "apply failed")
    {:ok, server} = Kura.fail_server(server)

    expect(Provisioner, :current_image_tag, fn %Server{id: id} ->
      assert id == server.id
      {:ok, deployment.image_tag}
    end)

    expect(Provisioner, :public_url, fn account_arg, %Server{id: id} ->
      assert account_arg.id == account.id
      assert id == server.id
      "https://localhost:4100"
    end)

    expect(Req, :get, fn "https://localhost:4100/up", _opts ->
      {:error, %Mint.TransportError{reason: {:tls_alert, ~c"unknown ca"}}}
    end)

    assert :ok = Reconciler.reconcile()

    assert %Server{status: :failed, current_image_tag: nil, url: nil} = Repo.get!(Server, server.id)
  end

  test "heals a failed server and applies drift to an active server in the same tick" do
    {_account_a, active_server, active_deployment} = create_server()
    {:ok, active_server} = Kura.activate_server(active_server, active_deployment.image_tag)
    mark_deployment_succeeded(active_deployment)

    {_account_b, failed_server, failed_deployment} = create_server()
    {:ok, _deployment} = Kura.mark_failed(failed_deployment, "apply failed")
    {:ok, failed_server} = Kura.fail_server(failed_server)

    stub(Tuist.Environment, :kura_runtime_image_tag, fn -> "sha-abcdef123456" end)

    stub(Provisioner, :current_image_tag, fn %Server{id: id} ->
      assert id in [active_server.id, failed_server.id]
      {:ok, "0.5.2"}
    end)

    expect(Provisioner, :rollout, fn %Server{id: id}, inputs ->
      assert id == active_server.id
      assert inputs.image_tag == "sha-abcdef123456"
      :ok
    end)

    assert :ok = Reconciler.reconcile()

    assert %Deployment{status: :running} =
             Repo.get_by!(Deployment, kura_server_id: active_server.id, image_tag: "sha-abcdef123456")

    assert %Server{status: :active, current_image_tag: "0.5.2"} = Repo.get!(Server, active_server.id)

    assert %Server{status: :active, current_image_tag: "0.5.2"} = Repo.get!(Server, failed_server.id)
    assert %Deployment{status: :failed} = Repo.get!(Deployment, failed_deployment.id)
  end

  test "heals a previously-active server forward to the drift image the controller eventually applied" do
    {_account, server, deployment} = create_server()
    {:ok, server} = Kura.activate_server(server, deployment.image_tag)
    mark_deployment_succeeded(deployment)

    {:ok, drift} = Kura.create_deployment(server, "sha-newimage123")
    {:ok, drift} = Kura.mark_running(drift)
    {:ok, _drift} = Kura.mark_failed(drift, "apply failed")
    {:ok, server} = Kura.fail_server(server)

    # The controller recovered and is now serving the drift image, not
    # the image the server used to serve. The projection's desired
    # image is the latest deployment's, so it heals forward to it.
    stub(Provisioner, :current_image_tag, fn %Server{id: id} ->
      assert id == server.id
      {:ok, "sha-newimage123"}
    end)

    assert :ok = Reconciler.reconcile()

    assert %Server{status: :active, current_image_tag: "sha-newimage123", observed_image_tag: "sha-newimage123"} =
             Repo.get!(Server, server.id)
  end

  test "records the observed image without flipping status while the cluster has not converged" do
    {_account, server, deployment} = create_server()
    {:ok, _deployment} = Kura.mark_failed(deployment, "apply failed")
    {:ok, server} = Kura.fail_server(server)

    stub(Provisioner, :current_image_tag, fn %Server{id: id} ->
      assert id == server.id
      {:ok, "0.4.0"}
    end)

    assert :ok = Reconciler.reconcile()

    server = Repo.get!(Server, server.id)
    assert server.status == :failed
    assert server.current_image_tag == nil
    assert server.observed_image_tag == "0.4.0"
    assert server.last_observed_at
  end

  test "marks a pending deployment running before succeeding an already-observed image" do
    {_account, server, deployment} = create_server()

    expect(Provisioner, :current_image_tag, fn %Server{id: id} ->
      assert id == server.id
      {:ok, deployment.image_tag}
    end)

    assert :ok = Reconciler.reconcile()

    assert %Deployment{status: :succeeded, started_at: started_at, finished_at: finished_at} =
             Repo.get!(Deployment, deployment.id)

    assert started_at
    assert finished_at

    assert %Server{status: :active, current_image_tag: "0.5.2", url: "http://localhost:4100"} =
             Repo.get!(Server, server.id)
  end

  defp create_server do
    user = AccountsFixtures.user_fixture()
    account = Accounts.get_account_from_user(user)

    {:ok, server} =
      Kura.create_server(%{
        account_id: account.id,
        region: "local-controller",
        image_tag: "0.5.2"
      })

    {account, server, List.first(server.deployments)}
  end

  defp mark_deployment_succeeded(deployment) do
    {:ok, deployment} = Kura.mark_running(deployment)
    {:ok, deployment} = Kura.mark_succeeded(deployment)
    deployment
  end
end
