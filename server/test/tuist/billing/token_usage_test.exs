defmodule Tuist.Billing.TokenUsageTest do
  use TuistTestSupport.Cases.DataCase

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Accounts.Account
  alias Tuist.Billing

  describe "create_token_usage/1" do
    test "creates token usage with valid attributes" do
      organization = organization_fixture()
      account = Tuist.Repo.get_by!(Account, organization_id: organization.id)

      attrs = %{
        input_tokens: 100,
        output_tokens: 50,
        model: "claude-sonnet-4-20250514",
        feature: "qa",
        feature_resource_id: UUIDv7.generate(),
        account_id: account.id,
        timestamp: DateTime.utc_now()
      }

      assert {:ok, token_usage} = Billing.create_token_usage(attrs)

      assert %{
               input_tokens: 100,
               output_tokens: 50,
               model: "claude-sonnet-4-20250514",
               feature: "qa"
             } = token_usage

      assert token_usage.account_id == account.id
    end

    test "validates required fields" do
      assert {:error, changeset} = Billing.create_token_usage(%{})

      assert errors_on(changeset) == %{
               input_tokens: ["can't be blank"],
               output_tokens: ["can't be blank"],
               model: ["can't be blank"],
               feature: ["can't be blank"],
               feature_resource_id: ["can't be blank"],
               account_id: ["can't be blank"],
               timestamp: ["can't be blank"]
             }
    end

    test "validates token counts are non-negative" do
      organization = organization_fixture()
      account = Tuist.Repo.get_by!(Account, organization_id: organization.id)

      attrs = %{
        input_tokens: -10,
        output_tokens: -5,
        model: "claude-sonnet-4-20250514",
        feature: "qa",
        feature_resource_id: UUIDv7.generate(),
        account_id: account.id,
        timestamp: DateTime.utc_now()
      }

      assert {:error, changeset} = Billing.create_token_usage(attrs)

      assert errors_on(changeset) == %{
               input_tokens: ["must be greater than or equal to 0"],
               output_tokens: ["must be greater than or equal to 0"]
             }
    end

    test "validates feature is in allowed list" do
      organization = organization_fixture()
      account = Tuist.Repo.get_by!(Account, organization_id: organization.id)

      attrs = %{
        input_tokens: 100,
        output_tokens: 50,
        model: "claude-sonnet-4-20250514",
        feature: "invalid_feature",
        feature_resource_id: UUIDv7.generate(),
        account_id: account.id,
        timestamp: DateTime.utc_now()
      }

      assert {:error, changeset} = Billing.create_token_usage(attrs)

      assert errors_on(changeset) == %{
               feature: ["is invalid"]
             }
    end
  end

  describe "token_usage_for_resource/2" do
    test "returns aggregated token usage for a specific resource" do
      organization = organization_fixture()
      account = Tuist.Repo.get_by!(Account, organization_id: organization.id)
      resource_id = UUIDv7.generate()

      {:ok, _} =
        Billing.create_token_usage(%{
          input_tokens: 100,
          output_tokens: 50,
          model: "claude-sonnet-4-20250514",
          feature: "qa",
          feature_resource_id: resource_id,
          account_id: account.id,
          timestamp: DateTime.utc_now()
        })

      {:ok, _} =
        Billing.create_token_usage(%{
          input_tokens: 200,
          output_tokens: 100,
          model: "claude-sonnet-4-20250514",
          feature: "qa",
          feature_resource_id: resource_id,
          account_id: account.id,
          timestamp: DateTime.utc_now()
        })

      usage = Billing.token_usage_for_resource("qa", resource_id)

      assert %{
               total_input_tokens: 300,
               total_output_tokens: 150,
               total_tokens: 450,
               average_tokens: 450
             } = usage
    end

    test "returns zero stats when no usage exists" do
      resource_id = UUIDv7.generate()
      usage = Billing.token_usage_for_resource("qa", resource_id)

      assert %{
               total_input_tokens: 0,
               total_output_tokens: 0,
               total_tokens: 0,
               average_tokens: 0
             } = usage
    end
  end

  describe "feature_token_usage_by_account/1" do
    test "returns token usage by account for a specific feature with 30-day and 12-month stats" do
      org1 = organization_fixture()
      org2 = organization_fixture()
      account1 = Tuist.Repo.get_by!(Account, organization_id: org1.id)
      account2 = Tuist.Repo.get_by!(Account, organization_id: org2.id)

      thirty_five_days_ago = DateTime.add(DateTime.utc_now(), -35, :day)
      twenty_days_ago = DateTime.add(DateTime.utc_now(), -20, :day)
      today = DateTime.utc_now()

      {:ok, _} =
        Billing.create_token_usage(%{
          input_tokens: 1000,
          output_tokens: 500,
          model: "claude-sonnet-4-20250514",
          feature: "qa",
          feature_resource_id: UUIDv7.generate(),
          account_id: account1.id,
          timestamp: thirty_five_days_ago
        })

      {:ok, _} =
        Billing.create_token_usage(%{
          input_tokens: 200,
          output_tokens: 100,
          model: "claude-sonnet-4-20250514",
          feature: "qa",
          feature_resource_id: UUIDv7.generate(),
          account_id: account1.id,
          timestamp: twenty_days_ago
        })

      {:ok, _} =
        Billing.create_token_usage(%{
          input_tokens: 300,
          output_tokens: 150,
          model: "claude-sonnet-4-20250514",
          feature: "qa",
          feature_resource_id: UUIDv7.generate(),
          account_id: account2.id,
          timestamp: today
        })

      {:ok, _} =
        Billing.create_token_usage(%{
          input_tokens: 100,
          output_tokens: 50,
          model: "gpt-4",
          feature: "qa",
          feature_resource_id: UUIDv7.generate(),
          account_id: account1.id,
          timestamp: today
        })

      usage_by_account = Billing.feature_token_usage_by_account("qa")

      assert length(usage_by_account) == 2

      first_account = List.first(usage_by_account)

      assert %{
               twelve_month: %{
                 total_input_tokens: 1300,
                 total_output_tokens: 650,
                 total_tokens: 1950,
                 average_tokens: 650
               },
               thirty_day: %{
                 total_input_tokens: 300,
                 total_output_tokens: 150,
                 total_tokens: 450,
                 average_tokens: 225
               }
             } = first_account

      assert first_account.account_id == account1.id

      second_account = List.last(usage_by_account)

      assert %{
               twelve_month: %{
                 total_input_tokens: 300,
                 total_output_tokens: 150,
                 total_tokens: 450,
                 average_tokens: 450
               },
               thirty_day: %{
                 total_input_tokens: 300,
                 total_output_tokens: 150,
                 total_tokens: 450,
                 average_tokens: 450
               }
             } = second_account

      assert second_account.account_id == account2.id
    end

    test "returns empty list when no usage exists for feature" do
      usage_by_account = Billing.feature_token_usage_by_account("nonexistent_feature")
      assert usage_by_account == []
    end
  end
end
