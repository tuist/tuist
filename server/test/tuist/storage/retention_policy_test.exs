defmodule Tuist.Storage.RetentionPolicyTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Accounts.Account
  alias Tuist.Billing
  alias Tuist.Storage.RetentionPolicy

  describe "current_plan/1" do
    test "returns the active subscription plan" do
      account = %Account{id: 1}

      expect(Billing, :get_current_active_subscription, fn ^account ->
        %{plan: :pro}
      end)

      assert RetentionPolicy.current_plan(account) == :pro
    end

    test "defaults to Air when the account has no active subscription" do
      account = %Account{id: 1}

      expect(Billing, :get_current_active_subscription, fn ^account ->
        nil
      end)

      assert RetentionPolicy.current_plan(account) == :air
    end
  end

  describe "retention_days/2" do
    test "returns plan-specific app preview retention" do
      assert RetentionPolicy.retention_days(:preview_app_build, :air) == 60
      assert RetentionPolicy.retention_days(:preview_app_build, :open_source) == 60
      assert RetentionPolicy.retention_days(:preview_app_build, :pro) == 180
      assert RetentionPolicy.retention_days(:preview_app_build, :enterprise) == 365
    end

    test "returns plan-specific build and test artifact retention" do
      assert RetentionPolicy.retention_days(:build_archive, :air) == 30
      assert RetentionPolicy.retention_days(:test_attachment, :air) == 30
      assert RetentionPolicy.retention_days(:build_archive, :pro) == 90
      assert RetentionPolicy.retention_days(:test_attachment, :pro) == 90
      assert RetentionPolicy.retention_days(:build_archive, :enterprise) == 365
      assert RetentionPolicy.retention_days(:test_attachment, :enterprise) == 365
    end

    test "returns short shard bundle retention" do
      assert RetentionPolicy.retention_days(:shard_bundle, :air) == 7
      assert RetentionPolicy.retention_days(:shard_bundle, :pro) == 14
      assert RetentionPolicy.retention_days(:shard_bundle, :enterprise) == 30
    end

    test "falls back to Air for unknown plan values" do
      assert RetentionPolicy.retention_days(:preview_app_build, :unknown) == 60
    end
  end
end
