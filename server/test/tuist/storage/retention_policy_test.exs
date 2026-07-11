defmodule Tuist.Storage.RetentionPolicyTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Accounts.Account
  alias Tuist.Billing
  alias Tuist.Billing.Subscription
  alias Tuist.Repo
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

  describe "current_plans/1" do
    test "returns active subscription plans for accounts in one query" do
      accounts = [%Account{id: 1}, %Account{id: 2}, %Account{id: 3}]

      expect(Repo, :all, fn %Ecto.Query{from: %{source: {"subscriptions", Subscription}}} ->
        [{1, :pro}, {3, :enterprise}]
      end)

      assert RetentionPolicy.current_plans(accounts) == %{1 => :pro, 2 => :air, 3 => :enterprise}
    end
  end

  describe "retention_days/2" do
    test "uses an explicit retention window without the hosted maximum" do
      assert RetentionPolicy.retention_days(:cache_artifact, :air, 120) == 120
      assert RetentionPolicy.retention_days(:shard_bundle, :air, 365) == 365
    end

    test "rejects invalid explicit retention windows" do
      assert_raise ArgumentError, fn -> RetentionPolicy.retention_days(:cache_artifact, :air, 0) end
      assert_raise ArgumentError, fn -> RetentionPolicy.retention_days(:cache_artifact, :air, -1) end
      assert_raise ArgumentError, fn -> RetentionPolicy.retention_days(:cache_artifact, :air, "30") end
    end

    test "returns cache artifact retention capped at 30 days" do
      assert RetentionPolicy.retention_days(:cache_artifact, :air) == 14
      assert RetentionPolicy.retention_days(:cache_artifact, :open_source) == 14
      assert RetentionPolicy.retention_days(:cache_artifact, :pro) == 30
      assert RetentionPolicy.retention_days(:cache_artifact, :enterprise) == 30

      assert RetentionPolicy.retention_days(:xcode_cache_artifact, :air) == 14
      assert RetentionPolicy.retention_days(:xcode_cache_artifact, :open_source) == 14
      assert RetentionPolicy.retention_days(:xcode_cache_artifact, :pro) == 30
      assert RetentionPolicy.retention_days(:xcode_cache_artifact, :enterprise) == 30
    end

    test "returns 30-day app preview retention for all plans" do
      assert RetentionPolicy.retention_days(:preview_app_build, :air) == 30
      assert RetentionPolicy.retention_days(:preview_app_build, :open_source) == 30
      assert RetentionPolicy.retention_days(:preview_app_build, :pro) == 30
      assert RetentionPolicy.retention_days(:preview_app_build, :enterprise) == 30

      assert RetentionPolicy.retention_days(:preview_icon, :air) == 30
      assert RetentionPolicy.retention_days(:preview_icon, :open_source) == 30
      assert RetentionPolicy.retention_days(:preview_icon, :pro) == 30
      assert RetentionPolicy.retention_days(:preview_icon, :enterprise) == 30
    end

    test "returns short build and run artifact retention for all plans" do
      assert RetentionPolicy.retention_days(:build_archive, :air) == 30
      assert RetentionPolicy.retention_days(:build_archive, :open_source) == 30
      assert RetentionPolicy.retention_days(:build_archive, :pro) == 30
      assert RetentionPolicy.retention_days(:build_archive, :enterprise) == 30

      assert RetentionPolicy.retention_days(:run_session, :air) == 30
      assert RetentionPolicy.retention_days(:run_session, :open_source) == 30
      assert RetentionPolicy.retention_days(:run_session, :pro) == 30
      assert RetentionPolicy.retention_days(:run_session, :enterprise) == 30
    end

    test "returns 30-day test artifact retention for all plans" do
      assert RetentionPolicy.retention_days(:test_attachment, :air) == 30
      assert RetentionPolicy.retention_days(:test_attachment, :open_source) == 30
      assert RetentionPolicy.retention_days(:test_attachment, :pro) == 30
      assert RetentionPolicy.retention_days(:test_attachment, :enterprise) == 30
    end

    test "returns short shard bundle retention" do
      assert RetentionPolicy.retention_days(:shard_bundle, :air) == 7
      assert RetentionPolicy.retention_days(:shard_bundle, :open_source) == 7
      assert RetentionPolicy.retention_days(:shard_bundle, :pro) == 14
      assert RetentionPolicy.retention_days(:shard_bundle, :enterprise) == 30
    end

    test "falls back to Air for unknown plan values" do
      assert RetentionPolicy.retention_days(:cache_artifact, :unknown) == 14
    end
  end

  describe "cutoff/2" do
    test "subtracts the selected retention window from now" do
      before_cutoff = DateTime.add(DateTime.utc_now(), -30, :day)

      cutoff = RetentionPolicy.cutoff(:cache_artifact, :enterprise)

      after_cutoff = DateTime.add(DateTime.utc_now(), -30, :day)

      assert DateTime.compare(cutoff, before_cutoff) in [:gt, :eq]
      assert DateTime.compare(cutoff, after_cutoff) in [:lt, :eq]
    end

    test "subtracts an explicit retention window from now" do
      before_cutoff = DateTime.add(DateTime.utc_now(), -120, :day)

      cutoff = RetentionPolicy.cutoff(:cache_artifact, :air, 120)

      after_cutoff = DateTime.add(DateTime.utc_now(), -120, :day)

      assert DateTime.compare(cutoff, before_cutoff) in [:gt, :eq]
      assert DateTime.compare(cutoff, after_cutoff) in [:lt, :eq]
    end
  end
end
