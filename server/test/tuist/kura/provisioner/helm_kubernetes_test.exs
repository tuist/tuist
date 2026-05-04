defmodule Tuist.Kura.Provisioner.HelmKubernetesTest do
  use ExUnit.Case, async: false
  use Mimic

  import ExUnit.CaptureLog

  alias Tuist.Kura.Provisioner.HelmKubernetes
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server

  setup :set_mimic_global

  describe "rollout/2" do
    test "writes kubeconfig and invokes the chart rollout script" do
      chart = chart_fixture("return true")
      put_chart_path(chart)

      stub(Tuist.Environment, :kura_kubeconfig, fn "local" -> "apiVersion: v1\nclusters: []\n" end)
      stub(Tuist.Environment, :app_url, fn -> "http://localhost:4000" end)
      stub(Tuist.Environment, :secret_key_tokens, fn -> nil end)
      stub(Tuist.License, :get_license, fn -> {:error, :missing} end)

      test_pid = self()
      region = local_region()

      assert :ok =
               HelmKubernetes.rollout("kura-tuist-local", %{
                 image_tag: "0.5.2",
                 account: %{name: "tuist"},
                 server: %Server{spec: :small, volume_size_gi: 25},
                 region: region,
                 on_log_line: fn line, stream -> send(test_pid, {:log_line, line, stream}) end
               })

      assert_receive {:log_line, "rollout started", :stdout}

      args = chart |> Path.join("rollout.args") |> File.read!() |> String.split("\n", trim: true)

      assert args == [
               "kura-tuist-local",
               "kura",
               "-f",
               Path.join(chart, "values-managed.yaml"),
               "-f",
               Path.join(chart, "values-managed-provider-local.yaml"),
               "-f",
               List.last(args)
             ]

      kubeconfig_path = chart |> Path.join("kubeconfig.env") |> File.read!()
      assert File.read!(kubeconfig_path) == "apiVersion: v1\nclusters: []\n"
      assert file_mode(kubeconfig_path) == 0o600

      values_path = List.last(args)
      assert File.read!(values_path) =~ "fullnameOverride: kura-tuist-local"
      assert file_mode(values_path) == 0o600
    end

    test "returns a tagged error when rollout exits non-zero" do
      chart = chart_fixture("return true", rollout_exit_status: 17)
      put_chart_path(chart)

      stub(Tuist.Environment, :kura_kubeconfig, fn "local" -> "apiVersion: v1\nclusters: []\n" end)
      stub(Tuist.Environment, :app_url, fn -> "http://localhost:4000" end)
      stub(Tuist.Environment, :secret_key_tokens, fn -> nil end)
      stub(Tuist.License, :get_license, fn -> {:error, :missing} end)

      assert {:error, "rollout exited with status 17"} =
               HelmKubernetes.rollout("kura-tuist-local", %{
                 image_tag: "0.5.2",
                 account: %{name: "tuist"},
                 server: %Server{spec: :small, volume_size_gi: 25},
                 region: local_region(),
                 on_log_line: fn _, _ -> :ok end
               })
    end
  end

  describe "destroy/2" do
    test "is idempotent when kubeconfig resolution fails" do
      stub(Tuist.Environment, :kura_kubeconfig, fn "eu-1" -> nil end)

      region = %Regions{id: "eu", provisioner_config: %{cluster_id: "eu-1", helm_overlay: "hetzner"}}

      assert capture_log(fn ->
               assert :ok = HelmKubernetes.destroy("kura-tuist-eu-1", region)
             end) =~ "destroy(kura-tuist-eu-1) skipped"
    end
  end

  describe "instance_values/5" do
    test "renders per-account values for the local kind overlay" do
      chart = chart_fixture("print('tuist hook')")

      stub(Tuist.Environment, :app_url, fn -> "http://localhost:4000" end)
      stub(Tuist.Environment, :secret_key_tokens, fn -> "jwt-secret" end)
      stub(Tuist.License, :get_license, fn -> {:ok, %{signing_key: "signing-secret"}} end)

      region = %Regions{
        id: "local",
        provisioner_config: %{
          cluster_id: "local",
          helm_overlay: "local",
          public_url: "http://localhost:4000"
        }
      }

      assert values =
               HelmKubernetes.instance_values(
                 "0.5.2",
                 %{name: "tuist"},
                 region,
                 %Server{spec: :small, volume_size_gi: 25},
                 chart
               )

      assert values["fullnameOverride"] == "kura-tuist-local"
      assert values["image"] == %{"tag" => "0.5.2"}
      assert values["config"] == %{"tenantId" => "tuist", "region" => "local"}
      assert values["extension"] == %{"enabled" => true, "script" => "print('tuist hook')"}
      assert values["persistence"] == %{"size" => "25Gi"}

      assert values["resources"] == %{
               "requests" => %{"cpu" => "250m", "memory" => "512Mi"},
               "limits" => %{"memory" => "1Gi"}
             }

      refute Map.has_key?(values, "ingress")

      env = Map.new(values["extraEnv"], &{&1["name"], &1["value"]})

      assert env["KURA_EXTENSION_HTTP_CLIENT_TUIST_BASE_URL"] == "http://host.docker.internal:4000"
      assert env["KURA_EXTENSION_JWT_VERIFIER_TUIST_SECRET"] == "jwt-secret"
      assert env["KURA_EXTENSION_SIGNER_TUIST_SECRET"] == "signing-secret"
    end

    test "renders ingress hosts from the public host template" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)
      stub(Tuist.Environment, :secret_key_tokens, fn -> nil end)
      stub(Tuist.License, :get_license, fn -> {:error, :missing} end)

      region = %Regions{
        id: "eu",
        provisioner_config: %{
          cluster_id: "eu-1",
          helm_overlay: "hetzner",
          public_host_template: "{account_handle}-{cluster_id}.kura.tuist.dev"
        }
      }

      values =
        HelmKubernetes.instance_values(
          "0.5.2",
          %{name: "tuist"},
          region,
          %Server{spec: :medium, volume_size_gi: 100},
          chart_fixture("return true")
        )

      assert values["ingress"]["hosts"] == [
               %{
                 "host" => "tuist-eu-1.kura.tuist.dev",
                 "paths" => [%{"path" => "/", "pathType" => "Prefix"}]
               }
             ]

      assert values["ingress"]["tls"] == [
               %{
                 "secretName" => "tuist-tls-cloudflare-origin-kura",
                 "hosts" => ["tuist-eu-1.kura.tuist.dev"]
               }
             ]
    end
  end

  describe "image_tag_from_image/1" do
    test "extracts the tag from a normal image reference" do
      assert HelmKubernetes.image_tag_from_image("ghcr.io/tuist/kura:0.5.2") == "0.5.2"
    end

    test "extracts the tag from an image reference that uses a registry port" do
      assert HelmKubernetes.image_tag_from_image("localhost:5001/tuist/kura:0.5.2") == "0.5.2"
    end

    test "returns nil when the image reference has no tag" do
      assert HelmKubernetes.image_tag_from_image("ghcr.io/tuist/kura") == nil
      assert HelmKubernetes.image_tag_from_image("ghcr.io/tuist/kura@sha256:abc123") == nil
    end

    test "extracts the tag from a reference that also has a digest" do
      assert HelmKubernetes.image_tag_from_image("ghcr.io/tuist/kura:0.5.2@sha256:abc123") == "0.5.2"
    end
  end

  defp chart_fixture(hook_script, opts \\ []) do
    root = Path.join(System.tmp_dir!(), "helm-kubernetes-test-#{System.unique_integer([:positive])}")
    hooks = Path.join(root, "hooks")
    File.mkdir_p!(hooks)
    File.write!(Path.join(hooks, "tuist.lua"), hook_script)

    rollout_exit_status = Keyword.get(opts, :rollout_exit_status, 0)

    rollout = Path.join(root, "rollout.sh")

    File.write!(
      rollout,
      "#!/usr/bin/env bash\n" <>
        "printf '%s\\n' \"$@\" > \"#{Path.join(root, "rollout.args")}\"\n" <>
        "printf '%s' \"$KUBECONFIG\" > \"#{Path.join(root, "kubeconfig.env")}\"\n" <>
        "echo \"rollout started\"\n" <>
        "exit #{rollout_exit_status}\n"
    )

    File.chmod!(rollout, 0o755)
    File.write!(Path.join(root, "values-managed.yaml"), "")
    File.write!(Path.join(root, "values-managed-provider-local.yaml"), "")
    File.write!(Path.join(root, "values-managed-provider-hetzner.yaml"), "")

    root
  end

  defp local_region do
    %Regions{
      id: "local",
      provisioner_config: %{
        cluster_id: "local",
        helm_overlay: "local",
        public_url: "http://localhost:4000"
      }
    }
  end

  defp put_chart_path(chart) do
    previous = Application.get_env(:tuist, :kura_chart_path)
    Application.put_env(:tuist, :kura_chart_path, chart)

    on_exit(fn ->
      if previous do
        Application.put_env(:tuist, :kura_chart_path, previous)
      else
        Application.delete_env(:tuist, :kura_chart_path)
      end
    end)
  end

  defp file_mode(path) do
    path |> File.stat!() |> Map.fetch!(:mode) |> Bitwise.band(0o777)
  end
end
