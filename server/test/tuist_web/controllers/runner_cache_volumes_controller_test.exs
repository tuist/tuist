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

  test "rejects workflow or unrelated service account credentials before touching storage" do
    expect(K8sClient, :create_controller_token_review, fn "agent-token" ->
      {:ok, %{namespace: Environment.runners_namespace(), name: "runner-job"}}
    end)

    result = Controller.report(conn(), %{"node_name" => "node", "id" => Ecto.UUID.generate()})
    assert result.status == 403
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
end
