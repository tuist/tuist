defmodule Tuist.Kubernetes.ClientTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Kubernetes.Client

  setup :set_mimic_from_context

  defmodule Env do
    @moduledoc false
    def get_env("KUBERNETES_SERVICE_HOST"), do: "kubernetes.default.svc"
    def get_env("KUBERNETES_SERVICE_PORT"), do: "443"
  end

  describe "apply/2" do
    @tag :tmp_dir
    test "uses server-side apply with the in-cluster service account", %{tmp_dir: tmp_dir} do
      token_path = Path.join(tmp_dir, "token")
      ca_path = Path.join(tmp_dir, "ca.crt")
      File.write!(token_path, "test-token\n")
      File.write!(ca_path, "test-ca")

      expect(Req, :request, fn opts ->
        assert opts[:method] == :patch

        assert opts[:url] ==
                 "https://kubernetes.default.svc:443/apis/kura.tuist.dev/v1alpha1/namespaces/kura/kurainstances/kura-tuist-eu-central-1"

        assert opts[:params] == %{"fieldManager" => "tuist-server", "force" => "true"}
        assert {"authorization", "Bearer test-token"} in opts[:headers]
        assert {"content-type", "application/apply-patch+yaml"} in opts[:headers]
        assert opts[:connect_options] == [transport_opts: [cacertfile: ca_path]]
        assert opts[:body] =~ "kind: KuraInstance"

        {:ok, %Req.Response{status: 200, body: %{"metadata" => %{"name" => "kura-tuist-eu-central-1"}}}}
      end)

      assert {:ok, %{"metadata" => %{"name" => "kura-tuist-eu-central-1"}}} =
               Client.apply(
                 %{
                   "apiVersion" => "kura.tuist.dev/v1alpha1",
                   "kind" => "KuraInstance",
                   "metadata" => %{"namespace" => "kura", "name" => "kura-tuist-eu-central-1"},
                   "spec" => %{"image" => "ghcr.io/tuist/kura:0.5.2"}
                 },
                 env: Env,
                 token_path: token_path,
                 ca_path: ca_path
               )
    end

    @tag :tmp_dir
    test "can use kubectl mode for local controller-backed testing", %{tmp_dir: tmp_dir} do
      kubeconfig_path = Path.join(tmp_dir, "kubeconfig")
      File.write!(kubeconfig_path, "apiVersion: v1")

      expect(System, :find_executable, fn "kubectl" -> "/usr/bin/kubectl" end)

      expect(MuonTrap, :cmd, fn "env", args, [stderr_to_stdout: true] ->
        assert [
                 "kubectl",
                 "--kubeconfig",
                 ^kubeconfig_path,
                 "apply",
                 "--server-side",
                 "--field-manager",
                 "tuist-server",
                 "--force-conflicts",
                 "-f",
                 manifest_path,
                 "-o",
                 "json"
               ] = args

        assert File.read!(manifest_path) =~ "kind: KuraInstance"
        {Jason.encode!(%{"metadata" => %{"name" => "kura-tuist-local-controller"}}), 0}
      end)

      assert {:ok, %{"metadata" => %{"name" => "kura-tuist-local-controller"}}} =
               Client.apply(
                 %{
                   "apiVersion" => "kura.tuist.dev/v1alpha1",
                   "kind" => "KuraInstance",
                   "metadata" => %{"namespace" => "kura", "name" => "kura-tuist-local-controller"},
                   "spec" => %{"image" => "ghcr.io/tuist/kura:0.5.2"}
                 },
                 mode: :kubectl,
                 kubeconfig_path: kubeconfig_path
               )
    end

    test "can use a token-based kubeconfig for remote clusters" do
      kubeconfig = kubeconfig(%{token: "region-token"})

      expect(Req, :request, fn opts ->
        assert opts[:method] == :patch

        assert opts[:url] ==
                 "https://kubernetes.us-east.example.com/apis/kura.tuist.dev/v1alpha1/namespaces/kura/kurainstances/kura-tuist-us-east-1"

        assert {"authorization", "Bearer region-token"} in opts[:headers]

        transport_opts = opts[:connect_options][:transport_opts]
        ca_path = Keyword.fetch!(transport_opts, :cacertfile)
        assert File.read!(ca_path) == "test-ca"

        {:ok, %Req.Response{status: 200, body: %{"metadata" => %{"name" => "kura-tuist-us-east-1"}}}}
      end)

      assert {:ok, %{"metadata" => %{"name" => "kura-tuist-us-east-1"}}} =
               Client.apply(
                 %{
                   "apiVersion" => "kura.tuist.dev/v1alpha1",
                   "kind" => "KuraInstance",
                   "metadata" => %{"namespace" => "kura", "name" => "kura-tuist-us-east-1"},
                   "spec" => %{"image" => "ghcr.io/tuist/kura:0.5.2"}
                 },
                 mode: :kubeconfig,
                 kubeconfig: kubeconfig
               )
    end

    test "can use a client-certificate kubeconfig for remote clusters" do
      kubeconfig = kubeconfig(%{client_certificate: "test-cert", client_key: "test-key"})

      expect(Req, :request, fn opts ->
        refute Enum.any?(opts[:headers], fn {key, _value} -> key == "authorization" end)

        transport_opts = opts[:connect_options][:transport_opts]
        assert File.read!(Keyword.fetch!(transport_opts, :cacertfile)) == "test-ca"
        assert File.read!(Keyword.fetch!(transport_opts, :certfile)) == "test-cert"
        assert File.read!(Keyword.fetch!(transport_opts, :keyfile)) == "test-key"

        {:ok, %Req.Response{status: 200, body: %{"metadata" => %{"name" => "kura-tuist-us-east-1"}}}}
      end)

      assert {:ok, %{"metadata" => %{"name" => "kura-tuist-us-east-1"}}} =
               Client.apply(
                 %{
                   "apiVersion" => "kura.tuist.dev/v1alpha1",
                   "kind" => "KuraInstance",
                   "metadata" => %{"namespace" => "kura", "name" => "kura-tuist-us-east-1"},
                   "spec" => %{"image" => "ghcr.io/tuist/kura:0.5.2"}
                 },
                 mode: :kubeconfig,
                 kubeconfig: kubeconfig
               )
    end

    test "rejects kubectl mode outside dev and test" do
      stub(Tuist.Environment, :dev?, fn -> false end)
      stub(Tuist.Environment, :test?, fn -> false end)

      assert {:error, "local kubectl Kubernetes client mode is only available in dev/test"} =
               Client.apply(
                 %{
                   "apiVersion" => "kura.tuist.dev/v1alpha1",
                   "kind" => "KuraInstance",
                   "metadata" => %{"namespace" => "kura", "name" => "kura-tuist-local-controller"},
                   "spec" => %{"image" => "ghcr.io/tuist/kura:0.5.2"}
                 },
                 mode: :kubectl,
                 kubeconfig_path: "/tmp/kubeconfig"
               )
    end
  end

  describe "generic verbs" do
    @tag :tmp_dir
    test "supports get, replace, patch, and delete over the in-cluster client", %{tmp_dir: tmp_dir} do
      token_path = Path.join(tmp_dir, "token")
      ca_path = Path.join(tmp_dir, "ca.crt")
      File.write!(token_path, "test-token\n")
      File.write!(ca_path, "test-ca")

      opts = [env: Env, token_path: token_path, ca_path: ca_path]

      expect(Req, :request, 4, fn request_opts ->
        assert request_opts[:url] == "https://kubernetes.default.svc:443/apis/example.test/v1/namespaces/kura/widgets/one"
        assert {"authorization", "Bearer test-token"} in request_opts[:headers]

        case request_opts[:method] do
          :get ->
            {:ok, %Req.Response{status: 200, body: %{"metadata" => %{"name" => "one"}}}}

          :put ->
            assert {"content-type", "application/json"} in request_opts[:headers]
            assert Jason.decode!(request_opts[:body]) == %{"spec" => %{"image" => "ghcr.io/tuist/kura:0.5.2"}}
            {:ok, %Req.Response{status: 200, body: %{"metadata" => %{"name" => "one"}}}}

          :patch ->
            assert {"content-type", "application/json-patch+json"} in request_opts[:headers]

            assert Jason.decode!(request_opts[:body]) == [
                     %{"op" => "replace", "path" => "/spec/image", "value" => "ghcr.io/tuist/kura:0.5.3"}
                   ]

            {:ok, %Req.Response{status: 200, body: %{"metadata" => %{"name" => "one"}}}}

          :delete ->
            {:ok, %Req.Response{status: 200, body: %{}}}
        end
      end)

      path = "/apis/example.test/v1/namespaces/kura/widgets/one"

      assert {:ok, %{"metadata" => %{"name" => "one"}}} = Client.get(path, opts)

      assert {:ok, %{"metadata" => %{"name" => "one"}}} =
               Client.replace(path, %{"spec" => %{"image" => "ghcr.io/tuist/kura:0.5.2"}}, opts)

      assert {:ok, %{"metadata" => %{"name" => "one"}}} =
               Client.patch(
                 path,
                 [%{"op" => "replace", "path" => "/spec/image", "value" => "ghcr.io/tuist/kura:0.5.3"}],
                 opts
               )

      assert :ok = Client.delete(path, opts)
    end
  end

  defp kubeconfig(%{token: token}) do
    kubeconfig_user("token: #{token}")
  end

  defp kubeconfig(%{client_certificate: cert, client_key: key}) do
    kubeconfig_user("""
    client-certificate-data: #{Base.encode64(cert)}
    client-key-data: #{Base.encode64(key)}
    """)
  end

  defp kubeconfig_user(user) do
    """
    apiVersion: v1
    current-context: us-east
    clusters:
      - name: us-east
        cluster:
          server: https://kubernetes.us-east.example.com
          certificate-authority-data: #{Base.encode64("test-ca")}
    contexts:
      - name: us-east
        context:
          cluster: us-east
          user: tuist
    users:
      - name: tuist
        user:
    #{indent(user, 8)}
    """
  end

  defp indent(contents, spaces) do
    padding = String.duplicate(" ", spaces)

    contents
    |> String.trim_trailing()
    |> String.split("\n")
    |> Enum.map_join("\n", &(padding <> &1))
  end
end
