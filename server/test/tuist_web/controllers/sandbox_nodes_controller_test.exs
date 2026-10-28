defmodule TuistWeb.SandboxNodesControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Kubernetes.Client, as: K8sClient

  defp connect_node(conn, headers) do
    headers
    |> Enum.reduce(conn, fn {name, value}, conn -> put_req_header(conn, name, value) end)
    |> get(~p"/api/internal/sandboxes/nodes/connect")
  end

  test "rejects a request without a bearer token", %{conn: conn} do
    reject(&K8sClient.create_sandbox_node_token_review/1)

    conn = connect_node(conn, [{"x-tuist-node-name", "node-a"}])

    assert json_response(conn, 401)["error"] == "missing bearer token"
  end

  test "rejects a token the apiserver does not authenticate", %{conn: conn} do
    expect(K8sClient, :create_sandbox_node_token_review, fn "bad-token" -> {:error, :unauthenticated} end)

    conn = connect_node(conn, [{"authorization", "Bearer bad-token"}, {"x-tuist-node-name", "node-a"}])

    assert json_response(conn, 401)["error"] == "invalid token"
  end

  test "rejects a principal that is not a service account", %{conn: conn} do
    expect(K8sClient, :create_sandbox_node_token_review, fn "user-token" -> {:error, :not_service_account} end)

    conn = connect_node(conn, [{"authorization", "Bearer user-token"}, {"x-tuist-node-name", "node-a"}])

    assert json_response(conn, 401)["error"] == "not a service account"
  end

  test "rejects a service account from another namespace", %{conn: conn} do
    expect(K8sClient, :create_sandbox_node_token_review, fn "runner-token" ->
      {:ok, %{namespace: "tuist-runners", name: "sandboxd", uid: "1"}}
    end)

    conn = connect_node(conn, [{"authorization", "Bearer runner-token"}, {"x-tuist-node-name", "node-a"}])

    assert json_response(conn, 401)["error"] == "wrong namespace"
  end

  test "rejects a connection without a node name", %{conn: conn} do
    expect(K8sClient, :create_sandbox_node_token_review, fn "token" ->
      {:ok, %{namespace: "tuist-sandboxes", name: "sandboxd", uid: "1"}}
    end)

    conn = connect_node(conn, [{"authorization", "Bearer token"}])

    assert json_response(conn, 400)["error"] == "missing node name"
  end

  test "rejects a node name that is not a kubernetes name", %{conn: conn} do
    expect(K8sClient, :create_sandbox_node_token_review, fn "token" ->
      {:ok, %{namespace: "tuist-sandboxes", name: "sandboxd", uid: "1"}}
    end)

    conn = connect_node(conn, [{"authorization", "Bearer token"}, {"x-tuist-node-name", "Node_A!"}])

    assert json_response(conn, 400)["error"] == "invalid node name"
  end

  test "rejects a node name other than the node the token is bound to", %{conn: conn} do
    expect(K8sClient, :create_sandbox_node_token_review, fn "token" ->
      {:ok, %{namespace: "tuist-sandboxes", name: "sandboxd", uid: "1", node_name: "node-b"}}
    end)

    conn = connect_node(conn, [{"authorization", "Bearer token"}, {"x-tuist-node-name", "node-a"}])

    assert json_response(conn, 401)["error"] == "node name does not match the token"
  end

  test "rejects a token that is not bound to a node", %{conn: conn} do
    expect(K8sClient, :create_sandbox_node_token_review, fn "token" ->
      {:ok, %{namespace: "tuist-sandboxes", name: "sandboxd", uid: "1", node_name: nil}}
    end)

    conn = connect_node(conn, [{"authorization", "Bearer token"}, {"x-tuist-node-name", "node-a"}])

    assert json_response(conn, 401)["error"] == "node name does not match the token"
  end

  test "answers 503 when the apiserver is unreachable", %{conn: conn} do
    expect(K8sClient, :create_sandbox_node_token_review, fn "token" -> {:error, :not_in_cluster} end)

    conn = connect_node(conn, [{"authorization", "Bearer token"}, {"x-tuist-node-name", "node-a"}])

    assert json_response(conn, 503)["error"] == "kubernetes unavailable"
  end

  test "native identity requires the current node and control Pod UIDs", %{conn: conn} do
    principal = %{
      namespace: "tuist-sandboxes",
      name: "tuist-macos-sandboxd",
      node_name: "mac-1",
      node_uid: "node-uid",
      pod_name: "control",
      pod_uid: "pod-uid"
    }

    for {node_uid, pod_uid, deleting, role} <- [
          {"replacement", "pod-uid", nil, "control"},
          {"node-uid", "replacement", nil, "control"},
          {"node-uid", "pod-uid", "now", "control"},
          {"node-uid", "pod-uid", nil, "execution"}
        ] do
      expect(K8sClient, :create_sandbox_node_token_review, fn "token" -> {:ok, principal} end)

      expect(K8sClient, :get_node, fn "mac-1" ->
        {:ok, %{"metadata" => %{"uid" => node_uid, "labels" => %{"kubernetes.io/os" => "darwin"}}}}
      end)

      expect(K8sClient, :get_pod, fn "tuist-sandboxes", "control" ->
        {:ok,
         %{
           "metadata" => %{
             "uid" => pod_uid,
             "deletionTimestamp" => deleting,
             "labels" => %{"tuist.dev/macos-sandbox-role" => role}
           }
         }}
      end)

      response = connect_node(conn, [{"authorization", "Bearer token"}, {"x-tuist-node-name", "mac-1"}])
      assert json_response(response, 401)["error"] == "node name does not match the token"
    end
  end
end
