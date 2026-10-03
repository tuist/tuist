defmodule Atlas.PolicyTest do
  use Atlas.DataCase, async: true

  alias Atlas.Policy

  @authenticated %{current_user: %{id: "user-123"}}
  @unauthenticated %{}

  describe "instance:read" do
    test "denies unauthenticated users" do
      assert {:error, :unauthorized} = Policy.authorize(:instance_read, @unauthenticated, %{})
      refute Policy.authorize?(:instance_read, @unauthenticated, %{})
    end

    test "allows authenticated users" do
      assert :ok = Policy.authorize(:instance_read, @authenticated, %{})
      assert Policy.authorize?(:instance_read, @authenticated, %{})
    end
  end

  describe "integration:write" do
    test "denies unauthenticated users" do
      assert {:error, :unauthorized} = Policy.authorize(:integration_write, @unauthenticated, %{})
    end

    test "denies when current_user is nil" do
      assert {:error, :unauthorized} =
               Policy.authorize(:integration_write, %{current_user: nil}, %{})
    end

    test "allows authenticated users" do
      assert :ok = Policy.authorize(:integration_write, @authenticated, %{})
    end
  end

  describe "integration:read" do
    test "denies unauthenticated users" do
      assert {:error, :unauthorized} = Policy.authorize(:integration_read, @unauthenticated, %{})
    end

    test "allows authenticated users" do
      assert :ok = Policy.authorize(:integration_read, @authenticated, %{})
    end
  end
end
