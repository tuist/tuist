defmodule Condukt.Sandbox.KubernetesConfigTest do
  use ExUnit.Case, async: true

  alias Condukt.Sandbox
  alias Condukt.Sandbox.Kubernetes

  test "rejects invalid heartbeat intervals before Kubernetes calls" do
    assert {:error, {:invalid_heartbeat_interval, 0}} =
             Sandbox.new(Kubernetes, conn: :fake, heartbeat_interval: 0)
  end

  test "rejects invalid workspace sources before Kubernetes calls" do
    assert {:error, ":workspace_source git URL cannot be empty"} =
             Sandbox.new(Kubernetes, conn: :fake, workspace_source: "")
  end
end
