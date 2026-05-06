defmodule Tuist.Kura.Provisioner.KubernetesControllerTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Kura.Provisioner.KubernetesController
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server

  setup :set_mimic_from_context

  describe "manifest/6" do
    @tag :tmp_dir
    test "renders a KuraInstance without a per-account compute spec", %{tmp_dir: tmp_dir} do
      chart = chart_fixture(tmp_dir, "return true")

      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)
      stub(Tuist.Environment, :secret_key_tokens, fn -> "jwt-secret" end)
      stub(Tuist.License, :get_license, fn -> {:ok, %{signing_key: "signing-secret"}} end)

      manifest =
        KubernetesController.manifest(
          "kura-tuist-eu-1",
          "0.5.2",
          %{name: "tuist"},
          eu_region(),
          %Server{volume_size_gi: 100, spec: :small},
          chart
        )

      assert manifest["apiVersion"] == "kura.tuist.dev/v1alpha1"
      assert manifest["kind"] == "KuraInstance"
      assert manifest["metadata"]["name"] == "kura-tuist-eu-1"
      assert manifest["metadata"]["namespace"] == "kura"

      spec = manifest["spec"]
      assert spec["accountHandle"] == "tuist"
      assert spec["tenantID"] == "tuist"
      assert spec["region"] == "eu"
      assert spec["image"] == "ghcr.io/tuist/kura:0.5.2"
      assert spec["publicHost"] == "tuist-eu-1.kura.tuist.dev"
      assert spec["storageClassName"] == "hcloud-volumes"
      assert spec["volumeSizeGi"] == 100
      assert spec["extensionScript"] == "return true"

      refute Map.has_key?(spec, "resources")
      refute Map.has_key?(spec, "podAnnotations")

      env = Map.new(spec["extraEnv"], &{&1["name"], &1["value"]})
      assert env["KURA_EXTENSION_HTTP_CLIENT_TUIST_BASE_URL"] == "https://tuist.dev"
      assert env["KURA_EXTENSION_JWT_VERIFIER_TUIST_SECRET"] == "jwt-secret"
      assert env["KURA_EXTENSION_SIGNER_TUIST_SECRET"] == "signing-secret"
    end
  end

  describe "public_url/3" do
    test "interpolates the production host template with the account handle" do
      assert KubernetesController.public_url("TUIST", eu_region(), "any-ref") == "https://tuist-eu-1.kura.tuist.dev"
    end
  end

  describe "resources_for/1" do
    test "does not expose per-account Kubernetes resources" do
      assert KubernetesController.resources_for(%Server{spec: :small}) == %{}
    end
  end

  defp chart_fixture(tmp_dir, hook_script) do
    root = Path.join(tmp_dir, "chart-#{System.unique_integer([:positive])}")
    hooks = Path.join(root, "hooks")
    File.mkdir_p!(hooks)
    File.write!(Path.join(hooks, "tuist.lua"), hook_script)
    root
  end

  defp eu_region do
    %Regions{
      id: "eu",
      provisioner_config: %{
        cluster_id: "eu-1",
        public_host_template: "{account_handle}-{cluster_id}.kura.tuist.dev",
        storage_class: "hcloud-volumes"
      }
    }
  end
end
