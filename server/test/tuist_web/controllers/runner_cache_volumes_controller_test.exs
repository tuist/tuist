defmodule TuistWeb.RunnerCacheVolumesControllerTest do
  use ExUnit.Case, async: true
  use Mimic

  import Plug.Conn

  alias Tuist.Environment
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners.CacheVolumes
  alias TuistWeb.RunnerCacheVolumesController, as: Controller

  defp conn do
    :post |> Plug.Test.conn("/report") |> put_req_header("authorization", "Bearer agent-token")
  end

  test "older agents get 404 for explicit commit modes, which they treat as unsupported" do
    assert %{plug: Controller, plug_opts: :authorize} =
             Phoenix.Router.route_info(
               TuistWeb.Router,
               "POST",
               "/api/internal/runners/cache-volumes/authorize",
               "localhost"
             )

    assert :error =
             Phoenix.Router.route_info(
               TuistWeb.Router,
               "POST",
               "/api/internal/runners/cache-volumes/authorize-commit",
               "localhost"
             )
  end

  test "rejects workflow or unrelated service account credentials before touching storage" do
    expect(K8sClient, :create_controller_token_review, fn "agent-token" ->
      {:ok, %{namespace: Environment.runners_namespace(), name: "runner-job"}}
    end)

    result = Controller.report(conn(), %{"node_name" => "node", "id" => Ecto.UUID.generate()})
    assert result.status == 403
  end

  test "workflow credentials cannot obtain image transfer URLs" do
    expect(K8sClient, :create_controller_token_review, fn "agent-token" ->
      {:ok, %{namespace: Environment.runners_namespace(), name: "runner-job"}}
    end)

    result = Controller.image(conn(), %{"node_name" => "node", "id" => Ecto.UUID.generate(), "operation" => "download"})
    assert result.status == 403
  end

  test "storage that is unavailable is a 503, which agents retry, and a conflict a 409" do
    namespace = Application.get_env(:tuist, :runner_cache_volumes_namespace, Environment.runners_namespace())
    name = Application.get_env(:tuist, :runner_cache_volumes_sa_name, "tuist-runner-cache-volumes")
    stub(K8sClient, :create_controller_token_review, fn "agent-token" -> {:ok, %{namespace: namespace, name: name}} end)
    params = %{"node_name" => "node", "id" => Ecto.UUID.generate(), "operation" => "complete"}

    expect(CacheVolumes, :image, fn "node", _, _ -> {:error, :unavailable} end)
    assert Controller.image(conn(), params).status == 503

    expect(CacheVolumes, :image, fn "node", _, _ -> {:error, :conflict} end)
    assert Controller.image(conn(), params).status == 409
  end

  test "missing token cannot instruct orphan deletion" do
    result = Controller.report(Plug.Test.conn(:post, "/report"), %{"node_name" => "node", "id" => Ecto.UUID.generate()})
    assert result.status == 403
  end

  test "trusted agent can reclaim orphan metadata and receives no-store" do
    namespace = Application.get_env(:tuist, :runner_cache_volumes_namespace, Environment.runners_namespace())
    name = Application.get_env(:tuist, :runner_cache_volumes_sa_name, "tuist-runner-cache-volumes")
    expect(K8sClient, :create_controller_token_review, fn "agent-token" -> {:ok, %{namespace: namespace, name: name}} end)
    id = Ecto.UUID.generate()
    expect(CacheVolumes, :report, fn "node", ^id, _ -> {:error, :not_found} end)
    result = Controller.report(conn(), %{"node_name" => "node", "id" => id})
    assert result.status == 200
    assert JSON.decode!(result.resp_body) == %{"action" => "delete"}
    assert get_resp_header(result, "cache-control") == ["no-store"]
  end

  test "trusted agent can forget an orphan only after reporting deleted storage" do
    namespace = Application.get_env(:tuist, :runner_cache_volumes_namespace, Environment.runners_namespace())
    name = Application.get_env(:tuist, :runner_cache_volumes_sa_name, "tuist-runner-cache-volumes")
    stub(K8sClient, :create_controller_token_review, fn "agent-token" -> {:ok, %{namespace: namespace, name: name}} end)
    id = Ecto.UUID.generate()
    stub(CacheVolumes, :report, fn "node", ^id, _ -> {:error, :not_found} end)

    for state <- ["allocated", "active", "sealed", "deleted"] do
      result = Controller.report(conn(), %{"node_name" => "node", "id" => id, "state" => state})
      assert result.status == 200
      assert JSON.decode!(result.resp_body) == %{"action" => if(state == "deleted", do: "forget", else: "delete")}
      assert get_resp_header(result, "cache-control") == ["no-store"]
    end
  end

  test "a capacity above the host maximum answers 507 without allocating" do
    namespace = Application.get_env(:tuist, :runner_cache_volumes_namespace, Environment.runners_namespace())
    name = Application.get_env(:tuist, :runner_cache_volumes_sa_name, "tuist-runner-cache-volumes")
    stub(K8sClient, :create_controller_token_review, fn "agent-token" -> {:ok, %{namespace: namespace, name: name}} end)
    params = %{"key" => "cache", "requested_volume_bytes" => 50_000_000_000, "max_volume_bytes" => 20_000_000_000}

    expect(CacheVolumes, :allocate, fn ^params -> {:error, :capacity} end)
    result = Controller.authorize(conn(), params)
    assert result.status == 507
    assert JSON.decode!(result.resp_body) == %{"error" => "capacity"}

    expect(CacheVolumes, :allocate, fn ^params -> {:error, :volume_limit} end)
    assert Controller.authorize(conn(), params).status == 403
  end

  test "allocations carry the chosen capacity and the saved head's size" do
    namespace = Application.get_env(:tuist, :runner_cache_volumes_namespace, Environment.runners_namespace())
    name = Application.get_env(:tuist, :runner_cache_volumes_sa_name, "tuist-runner-cache-volumes")
    stub(K8sClient, :create_controller_token_review, fn "agent-token" -> {:ok, %{namespace: namespace, name: name}} end)

    expect(CacheVolumes, :allocate, fn _ ->
      {:ok, %{id: "use", volume_bytes: 50_000_000_000, head_size_bytes: nil}}
    end)

    result = Controller.authorize(conn(), %{})
    assert result.status == 200
    assert JSON.decode!(result.resp_body) == %{"id" => "use", "volume_bytes" => 50_000_000_000, "head_size_bytes" => nil}
  end

  test "only the storage agent can request a checkout" do
    assert %{plug: Controller, plug_opts: :checkout} =
             Phoenix.Router.route_info(
               TuistWeb.Router,
               "POST",
               "/api/internal/runners/cache-volumes/checkout",
               "localhost"
             )

    expect(K8sClient, :create_controller_token_review, fn "agent-token" ->
      {:ok, %{namespace: Environment.runners_namespace(), name: "runner-job"}}
    end)

    result = Controller.checkout(conn(), %{"pod_name" => "pod", "node_name" => "node"})
    assert result.status == 403
  end

  test "an unknown checkout request is refused without allocating anything" do
    namespace = Application.get_env(:tuist, :runner_cache_volumes_namespace, Environment.runners_namespace())
    name = Application.get_env(:tuist, :runner_cache_volumes_sa_name, "tuist-runner-cache-volumes")
    expect(K8sClient, :create_controller_token_review, fn "agent-token" -> {:ok, %{namespace: namespace, name: name}} end)

    result = Controller.checkout(conn(), %{"node_name" => "node"})
    assert result.status == 403
    assert CacheVolumes.checkout_key() == "checkout"
  end
end
