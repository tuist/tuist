defmodule TuistWeb.OpsAccountLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Accounts
  alias Tuist.Billing
  alias Tuist.Kura
  alias Tuist.Kura.Server
  alias Tuist.Repo
  alias Tuist.Runners.Concurrency
  alias Tuist.Runners.Prepaid
  alias Tuist.Runners.Trials
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  setup :verify_on_exit!

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    conn = log_in_user(conn, user)

    stub(Accounts, :tuist_operator?, fn _ -> true end)
    # Default the balance away so no test in this file reaches Stripe on
    # mount. The balance itself is covered in Tuist.Runners.PrepaidTest.
    stub(Prepaid, :balance, fn _account -> nil end)
    stub(Billing, :sync_runner_subscription_items, fn _account -> {:ok, :unchanged} end)

    %{conn: conn, user: user}
  end

  test "renders account billing controls", %{conn: conn, user: user} do
    {:ok, _lv, html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

    assert html =~ user.account.name
    assert html =~ "Plan &amp; billing"
    assert html =~ "Kura"
    assert html =~ "Runner concurrency"
    assert html =~ "value=\"12\""
  end

  test "toggles the account's dashboard visibility", %{conn: conn, user: user} do
    {:ok, lv, html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

    assert html =~ "Make public"

    html = lv |> element("button", "Make public") |> render_click()

    assert html =~ "Make private"
    assert {:ok, %{visibility: :public}} = Accounts.get_account_by_id(user.account.id)

    lv |> element("button", "Make private") |> render_click()

    assert {:ok, %{visibility: :private}} = Accounts.get_account_by_id(user.account.id)
  end

  test "updates platform-specific runner concurrency limits", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

    lv
    |> form("#runner-concurrency-form", %{
      "account" => %{
        "runner_linux_vcpus_limit" => "48",
        "runner_linux_memory_gb_limit" => "96",
        "runner_macos_vcpus_limit" => "18",
        "runner_macos_memory_gb_limit" => "42"
      }
    })
    |> render_submit()

    assert Concurrency.limits_for(user.account, :linux) == %{vcpus: 48, memory_gb: 96}
    assert Concurrency.limits_for(user.account, :macos) == %{vcpus: 18, memory_gb: 42}
  end

  test "links Kura servers to their latest deployment", %{conn: conn, user: user} do
    {:ok, server} =
      Kura.create_server(%{
        account_id: user.account.id,
        region: "local-controller",
        image_tag: "0.5.2"
      })

    deployment = List.first(server.deployments)

    {:ok, _lv, html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

    assert html =~ "0.5.2"
    refute html =~ "kura@0.5.2"
    assert html =~ ~p"/ops/accounts/#{user.account.id}/kura/deployments/#{deployment.id}"
  end

  test "shows the claim each instance actually holds", %{conn: conn, user: user} do
    stub(Tuist.Environment, :tuist_hosted?, fn -> true end)

    # Pinned: what this instance's volumes were created at, which diverges from
    # what its account would be sized at today for as long as it holds them, and
    # nothing converges the two on its own.
    Repo.insert!(%Server{
      account_id: user.account.id,
      region: "us-east",
      status: :active,
      url: "https://acme-us-east-1.kura.tuist.dev",
      current_image_tag: "0.5.2",
      provisioner_node_ref: "kura-#{user.account.id}-us-east",
      storage_claim_size: "50Gi"
    })

    # Pins nothing, and its region sizes every instance alike rather than per
    # account, so it holds the region's own claim. Reading the pinned column
    # alone reported "None" here while the instance was reserving 10Gi.
    Repo.insert!(%Server{
      account_id: user.account.id,
      region: "local-controller",
      status: :active,
      url: "http://localhost:4100",
      current_image_tag: "0.5.2",
      provisioner_node_ref: "kura-#{user.account.id}-local-controller"
    })

    {:ok, _lv, html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

    assert html =~ "50Gi"
    assert html =~ "10Gi"
  end

  test "resolves an unpinned instance in a per-account region against the override", %{conn: conn, user: user} do
    stub(Tuist.Environment, :tuist_hosted?, fn -> true end)

    # A governed region pins at creation, so this row is the state the resolution
    # exists to cover rather than one the product creates. It holds whatever the
    # account resolves to, which is the override once there is one.
    Repo.insert!(%Server{
      account_id: user.account.id,
      region: "us-east",
      status: :active,
      url: "https://acme-us-east-1.kura.tuist.dev",
      current_image_tag: "0.5.2",
      provisioner_node_ref: "kura-#{user.account.id}-us-east"
    })

    {:ok, _lv, html} = live(conn, ~p"/ops/accounts/#{user.account.id}")
    assert html =~ "8Gi"

    {:ok, _} = Kura.update_storage_claim_override(user.account, %{"kura_storage_claim_size" => "24Gi"})

    {:ok, _lv, html} = live(conn, ~p"/ops/accounts/#{user.account.id}")
    assert html =~ "24Gi"
  end

  test "sets a claim override and re-pins the instance it rebuilds", %{conn: conn, user: user} do
    stub(Tuist.Environment, :tuist_hosted?, fn -> true end)

    server =
      Repo.insert!(%Server{
        account_id: user.account.id,
        region: "us-east",
        status: :active,
        url: "https://acme-us-east-1.kura.tuist.dev",
        current_image_tag: "0.5.2",
        provisioner_node_ref: "kura-#{user.account.id}-us-east",
        storage_claim_size: "8Gi"
      })

    {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

    html =
      lv
      |> form("#kura-storage-claim-form", account: %{kura_storage_claim_size: "40Gi"})
      |> render_submit()

    assert Kura.storage_claim_override(user.account) == "40Gi"

    # Re-pinned, which is what carries the new claim into the manifest and has
    # the controller rebuild the volumes that no longer match it.
    assert Repo.get!(Server, server.id).storage_claim_size == "40Gi"

    # And the table the operator is looking at reflects it without a reload.
    assert html =~ "40Gi"
  end

  test "clears the override from the form and returns the account to its plan", %{conn: conn, user: user} do
    stub(Tuist.Environment, :tuist_hosted?, fn -> true end)

    {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

    lv
    |> form("#kura-storage-claim-form", account: %{kura_storage_claim_size: "40Gi"})
    |> render_submit()

    lv
    |> form("#kura-storage-claim-form", account: %{kura_storage_claim_size: ""})
    |> render_submit()

    assert Kura.storage_claim_override(user.account) == nil
  end

  test "refuses a claim below the floor a ring can be derived from", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

    html =
      lv
      |> form("#kura-storage-claim-form", account: %{kura_storage_claim_size: "4Gi"})
      |> render_submit()

    assert html =~ "must be at least 8Gi"
    assert Kura.storage_claim_override(user.account) == nil
  end

  test "one-click upgrade when the Stripe customer already has billing details", %{conn: conn, user: user} do
    stub(Stripe.Customer, :retrieve, fn _customer_id ->
      {:ok,
       %Stripe.Customer{
         name: "Acme",
         email: "billing@acme.test",
         address: %{
           line1: "1 Market St",
           city: "SF",
           postal_code: "94103",
           country: "US"
         }
       }}
    end)

    expect(Billing, :upgrade_to_enterprise, fn account, params ->
      assert account.id == user.account.id
      assert params == %{cadence: "monthly"}
      {:ok, %{id: "sub_fake"}}
    end)

    {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

    render_hook(lv, "initiate_enterprise_upgrade", %{})
  end

  test "opens the enterprise form when the Stripe customer has no address", %{conn: conn, user: user} do
    stub(Stripe.Customer, :retrieve, fn _customer_id ->
      {:ok, %Stripe.Customer{name: "Acme", email: "acme@test", address: nil}}
    end)

    {:ok, lv, initial_html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

    refute initial_html =~ "Upgrade #{user.account.name} to Enterprise"

    html = render_hook(lv, "initiate_enterprise_upgrade", %{})

    assert html =~ "Upgrade #{user.account.name} to Enterprise"
  end

  test "submits the enterprise form with the collected billing details", %{conn: conn, user: user} do
    expect(Billing, :upgrade_to_enterprise, fn account, params ->
      assert account.id == user.account.id
      assert params.name == "Acme Corp"
      assert params.billing_email == "billing@acme.test"
      assert params.cadence == "yearly"
      assert params.address.line1 == "1 Market St"
      assert params.address.city == "San Francisco"
      assert params.address.postal_code == "94103"
      assert params.address.country == "US"
      {:ok, %{id: "sub_fake"}}
    end)

    {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

    render_hook(lv, "submit_enterprise_upgrade", %{
      "name" => "Acme Corp",
      "billing_email" => "billing@acme.test",
      "address_line1" => "1 Market St",
      "address_line2" => "",
      "address_city" => "San Francisco",
      "address_state" => "CA",
      "address_postal_code" => "94103",
      "address_country" => "us",
      "cadence" => "yearly"
    })
  end

  test "Cancel plan cancels the active subscription at period end", %{conn: conn, user: user} do
    subscription = BillingFixtures.subscription_fixture(account_id: user.account.id, plan: :pro)

    expect(Billing, :cancel_subscription_at_period_end, fn sub ->
      assert sub.id == subscription.id
      {:ok, %{id: subscription.subscription_id, cancel_at_period_end: true}}
    end)

    {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

    render_hook(lv, "cancel_plan", %{})
  end

  describe "prepaid runner minutes" do
    test "quotes the money as minutes are typed, before anything is charged", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

      reject(&Prepaid.bill_prepaid_minutes/3)

      html =
        lv
        |> form("#prepaid-minutes-form", %{"minutes" => "10000"})
        |> render_change()

      assert html =~ "600.00"
      assert html =~ "750.00"
    end

    test "adds the charge to the next invoice rather than granting credit now", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

      expect(Prepaid, :bill_prepaid_minutes, fn account, minutes ->
        assert account.id == user.account.id
        assert minutes == 10_000
        {:ok, %{id: "ii_1"}}
      end)

      # `expect` above is the assertion: it pins the account and the
      # minute count, and verify_on_exit! fails the test if the charge
      # was never created.
      lv
      |> form("#prepaid-minutes-form", %{"minutes" => "10000"})
      |> render_submit()
    end

    test "refuses a minute count that is not a positive whole number", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

      reject(&Prepaid.bill_prepaid_minutes/3)

      # `reject` is the assertion: nothing may reach Stripe for any of
      # these, so no charge is created from a malformed minute count.
      for value <- ["0", "-5", "abc", "1.5", ""] do
        lv
        |> form("#prepaid-minutes-form", %{"minutes" => value})
        |> render_submit()
      end
    end

    test "warns when the account has no subscription to bill against", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

      assert has_element?(lv, "#prepaid-no-subscription-alert")
      # The body, not just the alert: it only renders at one size.
      assert render(lv) =~ "would sit unbilled"
    end

    test "lists what the account holds in minutes rather than money", %{conn: conn, user: user} do
      # Ops reads this to answer "how much runner time is left", and the
      # account bought minutes, not a sum of money. The money is an
      # implementation detail of how Stripe carries them.
      stub(Prepaid, :balance, fn _account ->
        %{
          available: Money.new(75_000, :USD),
          expires_at: ~U[2027-01-01 00:00:00Z],
          grants: [
            %{
              id: "credgr_1",
              kind: "prepaid",
              available: Money.new(75_000, :USD),
              available_minutes: 10_000,
              expires_at: ~U[2027-01-01 00:00:00Z]
            }
          ]
        }
      end)

      {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

      assert has_element?(lv, "#prepaid-balance-table", "10,000")
      assert has_element?(lv, "#prepaid-balance-table", "January 1, 2027")
      refute render(lv) =~ "750.00$"
    end
  end

  describe "runner trial" do
    test "says why the trial could not start instead of appearing to do nothing", %{conn: conn, user: user} do
      # The page renders no flash of its own and nothing renders one for
      # it, so a failed transition was completely silent: the button
      # stayed put and no reason reached the operator.
      stub(Billing, :sync_runner_subscription_items, fn _account -> {:error, :stripe_unavailable} end)

      {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

      html = lv |> element("button", "Start runner trial") |> render_click()

      assert html =~ "Could not start the trial"
      assert html =~ "stripe_unavailable"
      refute Trials.on_trial?(Repo.reload!(user.account))
    end

    test "starts a trial, which stops runner usage being billable", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

      refute has_element?(lv, "#runner-trial-active-alert")

      lv |> element("button", "Start runner trial") |> render_click()

      assert has_element?(lv, "#runner-trial-active-alert")

      {:ok, account} = Accounts.get_account_by_id(user.account.id)
      assert Trials.on_trial?(account)
    end

    test "cancelling puts the account back on billable runner usage", %{conn: conn, user: user} do
      {:ok, _account} = Trials.start(user.account)

      {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")
      assert has_element?(lv, "#runner-trial-active-alert")
      assert render(lv) =~ "may become billable when the item is added"

      lv |> element("button", "Cancel runner trial") |> render_click()

      refute has_element?(lv, "#runner-trial-active-alert")

      {:ok, account} = Accounts.get_account_by_id(user.account.id)
      refute Trials.on_trial?(account)
    end

    test "reconciles the subscription's runner items when the trial changes", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

      expect(Billing, :sync_runner_subscription_items, fn account ->
        assert Trials.on_trial?(account)
        {:ok, :unchanged}
      end)

      lv |> element("button", "Start runner trial") |> render_click()
    end
  end
end
