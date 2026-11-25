defmodule SymptomsWeb.BearerAuthTest do
  use ExUnit.Case, async: true
  use Mimic

  import Plug.Conn
  import Plug.Test

  alias SymptomsWeb.BearerAuth

  @moduletag :tmp_dir
  @audience "tuist-symptoms-api"

  setup %{tmp_dir: dir} do
    path = Path.join(dir, "token")
    File.write!(path, "reviewer-1\n")

    config = [
      server_namespace: "tuist-production",
      server_service_account: "tuist-server",
      base_url: "https://kube.test",
      token_path: path,
      ca_file: Path.join(dir, "ca.crt")
    ]

    %{config: config, path: path}
  end

  defp request(config, token \\ "caller-token") do
    :get |> conn("/api/v1/symptoms/log") |> put_req_header("authorization", "Bearer " <> token) |> BearerAuth.call(config)
  end

  defp status(overrides \\ %{}) do
    Map.merge(
      %{
        "authenticated" => true,
        "audiences" => [@audience],
        "user" => %{"username" => "system:serviceaccount:tuist-production:tuist-server"}
      },
      overrides
    )
  end

  defp reply(status), do: {:ok, %Req.Response{status: 201, body: %{"status" => status}}}

  test "validates the scoped caller through Kubernetes and rereads the rotating reviewer token", %{
    config: config,
    path: path
  } do
    expect(Req, :post, fn url, opts ->
      assert url == "https://kube.test/apis/authentication.k8s.io/v1/tokenreviews"

      assert opts[:json] == %{
               apiVersion: "authentication.k8s.io/v1",
               kind: "TokenReview",
               spec: %{token: "caller-token", audiences: [@audience]}
             }

      assert opts[:auth] == {:bearer, "reviewer-1"}
      assert opts[:connect_options][:transport_opts][:cacertfile] == config[:ca_file]
      assert opts[:redirect] == false
      assert opts[:retry] == false
      reply(status())
    end)

    refute request(config).halted
    File.write!(path, "reviewer-2\n")

    expect(Req, :post, fn _, opts ->
      assert opts[:auth] == {:bearer, "reviewer-2"}
      reply(status())
    end)

    refute request(config).halted
  end

  test "rejects expired tokens, other namespaces/accounts, wrong and absent audiences", %{config: config} do
    for rejected <- [
          status(%{"authenticated" => false}),
          status(%{"user" => %{"username" => "system:serviceaccount:other:tuist-server"}}),
          status(%{"user" => %{"username" => "system:serviceaccount:tuist-production:other"}}),
          status(%{"audiences" => ["tuist-symptoms-state"]}),
          Map.delete(status(), "audiences"),
          %{}
        ] do
      expect(Req, :post, fn _, _ -> reply(rejected) end)
      conn = request(config)
      assert conn.halted
      assert conn.status == 401
    end
  end

  test "missing, malformed and duplicate credentials never reach Kubernetes", %{config: config} do
    reject(&Req.post/2)

    for headers <- [
          [],
          [{"authorization", "Basic caller-token"}],
          [{"authorization", "Bearer "}],
          [{"authorization", "Bearer a"}, {"authorization", "Bearer b"}]
        ] do
      conn = %{conn(:get, "/api/v1/symptoms/log") | req_headers: headers}
      assert BearerAuth.call(conn, config).status == 401
    end
  end

  test "fails closed on review outages, malformed responses and missing reviewer credentials", %{
    config: config,
    path: path
  } do
    for result <- [
          {:error, %Req.TransportError{reason: :timeout}},
          {:ok, %Req.Response{status: 403, body: %{}}},
          {:ok, %Req.Response{status: 200, body: %{}}}
        ] do
      expect(Req, :post, fn _, _ -> result end)
      assert request(config).status == 503
    end

    reject(&Req.post/2)
    File.write!(path, "\n")
    assert request(config).status == 503
    File.rm!(path)
    assert request(config).status == 503
  end

  test "fails closed when the trusted principal is unconfigured", %{config: config} do
    reject(&Req.post/2)
    assert request(Keyword.put(config, :server_namespace, nil)).status == 503
  end
end
