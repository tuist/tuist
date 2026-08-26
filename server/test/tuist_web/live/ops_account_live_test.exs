defmodule TuistWeb.OpsAccountLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Accounts
  alias Tuist.Billing
  alias Tuist.Kura
  alias Tuist.Kura.ClaimProposal
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

  test "resolves an unpinned instance in a per-account region against the sized claim", %{conn: conn, user: user} do
    stub(Tuist.Environment, :tuist_hosted?, fn -> true end)

    # A governed region pins at creation, so this row is the state the resolution
    # exists to cover rather than one the product creates. It holds whatever the
    # account resolves to, which is the sized claim once there is one.
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

    :ok = Tuist.Kura.PlacerClaims.put(user.account, "24Gi")

    {:ok, _lv, html} = live(conn, ~p"/ops/accounts/#{user.account.id}")
    assert html =~ "24Gi"
  end

  test "surfaces each pod's reported disk state", %{conn: conn, user: user} do
    stub(Tuist.Environment, :tuist_hosted?, fn -> true end)

    Repo.insert!(%Server{
      account_id: user.account.id,
      region: "us-east",
      status: :active,
      url: "https://acme-us-east-1.kura.tuist.dev",
      current_image_tag: "0.5.2",
      provisioner_node_ref: "kura-#{user.account.id}-us-east",
      storage_claim_size: "25Gi"
    })

    captured_at = NaiveDateTime.truncate(NaiveDateTime.add(NaiveDateTime.utc_now(), -3_600), :second)

    Tuist.IngestRepo.insert_all(Tuist.Kura.StorageSnapshot, [
      %{
        event_id: "ops-snap-#{user.account.id}",
        account_id: user.account.id,
        node_id: "kura-#{user.account.id}-us-east-0",
        region: "us-east",
        captured_at: captured_at,
        ring_budget_bytes: 26_843_545_600,
        desired_segment_count: 50,
        live_segment_count: 24,
        live_segment_bytes: 12_884_901_888,
        oldest_segment_created_at: captured_at,
        newest_content_at: captured_at,
        inserted_at: captured_at
      }
    ])

    {:ok, _lv, html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

    assert html =~ "kura-#{user.account.id}-us-east-0"
    assert html =~ "12.9 GB of 26.8 GB"
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
      assert params == %{}
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
      # The form no longer offers a cadence, and a stale one posted at it
      # must not resurrect the retired yearly price.
      refute Map.has_key?(params, :cadence)
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

      reject(&Prepaid.set_minutes/3)

      html =
        lv
        |> form("#prepaid-minutes-form", %{"minutes" => "10000"})
        |> render_change()

      assert html =~ "600.00"
      assert html =~ "750.00"
    end

    test "shows the new balance without waiting for a reload", %{conn: conn, user: user} do
      # The minutes are granted as the charge is created, so the table
      # has to be re-read. Assigning it only at mount is what made the
      # button look like it did nothing.
      grant = fn minutes ->
        %{
          available: Money.new(minutes * 75, :USD),
          expires_at: ~U[2026-09-01 00:00:00Z],
          grants: [
            %{
              id: "credgr_1",
              kind: "prepaid",
              available: Money.new(minutes * 75, :USD),
              available_minutes: minutes,
              expires_at: ~U[2026-09-01 00:00:00Z]
            }
          ]
        }
      end

      # Keyed on the charge rather than a call count: the page reads the
      # balance once for the dead render and again on connect, so a
      # counter would have advanced before the form was ever submitted.
      {:ok, billed} = Agent.start_link(fn -> false end)

      stub(Prepaid, :set_minutes, fn _account, _minutes ->
        Agent.update(billed, fn _ -> true end)
        {:ok, %{id: "ii_1"}}
      end)

      stub(Prepaid, :balance, fn _account ->
        if Agent.get(billed, & &1), do: grant.(10_100), else: grant.(10_000)
      end)

      {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

      assert has_element?(lv, "#prepaid-balance-table", "10,000")

      html =
        lv
        |> form("#prepaid-minutes-form", %{"minutes" => "100"})
        |> render_submit()

      assert html =~ "10,100"
    end

    test "sets the balance to the figure typed rather than adding to it", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

      expect(Prepaid, :set_minutes, fn account, minutes ->
        assert account.id == user.account.id
        assert minutes == 10_000
        {:ok, %{id: "ii_1"}}
      end)

      # `expect` above is the assertion: it pins the account and the
      # minute count, and verify_on_exit! fails the test if nothing was
      # set.
      lv
      |> form("#prepaid-minutes-form", %{"minutes" => "10000"})
      |> render_submit()
    end

    test "arrives prefilled with what the account already holds", %{conn: conn, user: user} do
      stub(Prepaid, :balance, fn _account ->
        %{
          available: Money.new(750_000, :USD),
          expires_at: ~U[2026-09-01 00:00:00Z],
          grants: [
            %{
              id: "credgr_1",
              kind: "prepaid",
              available: Money.new(750_000, :USD),
              available_minutes: 10_000,
              expires_at: ~U[2026-09-01 00:00:00Z]
            }
          ]
        }
      end)

      {:ok, _lv, html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

      assert html =~ ~s(id="prepaid-minutes-input")
      assert html =~ ~s(value="10000")
    end

    test "refuses a minute count that is not a whole number at or above zero", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

      # Arity 2, which is what the page calls. Rejecting /3 rejected a
      # head nothing invokes, so this asserted nothing at all.
      reject(&Prepaid.set_minutes/2)

      for value <- ["-5", "abc", "1.5", ""] do
        lv
        |> form("#prepaid-minutes-form", %{"minutes" => value})
        |> render_submit()
      end
    end

    test "says the balance was cleared rather than quoting a charge", %{conn: conn, user: user} do
      # Zero invoices nothing, so quoting a minute's worth told the
      # operator 0.06$ had been added to a bill that gained no line.
      stub(Prepaid, :set_minutes, fn _account, _minutes -> {:ok, :cleared} end)

      {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

      lv
      |> form("#prepaid-minutes-form", %{"minutes" => "0"})
      |> render_submit()

      # Read off the flash itself: the page carries rates elsewhere, so
      # asserting against the whole render proves nothing.
      flash = lv |> element("#ops-account-flash-info") |> render()

      assert flash =~ "no longer holds any prepaid runner minutes"
      refute flash =~ "next invoice"
      refute flash =~ "0.06"
    end

    test "clears the balance when set to zero", %{conn: conn, user: user} do
      # Zero is a figure to set, not a malformed one: it is how an
      # account's minutes are taken away.
      {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

      expect(Prepaid, :set_minutes, fn account, minutes ->
        assert account.id == user.account.id
        assert minutes == 0
        {:ok, :cleared}
      end)

      lv
      |> form("#prepaid-minutes-form", %{"minutes" => "0"})
      |> render_submit()
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
      # The panel promises the trial's minutes stay free rather than
      # warning that they might not; Tuist.BillingTest covers the
      # proration parameter that makes that true.
      assert render(lv) =~ "Minutes it ran during the trial stay free"

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

  describe "claim sizing proposals" do
    setup %{user: user} do
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

      proposal =
        Repo.insert!(%ClaimProposal{
          account_id: user.account.id,
          region: "us-east",
          direction: :grow,
          current_claim_size: "8Gi",
          recommended_claim_size: "16Gi",
          evidence: %{
            "signal" => "shed_age_below_retention_floor",
            "region" => "us-east",
            "window_days" => 14,
            "retention_floor_seconds" => 86_400,
            "median_shed_age_seconds" => 43_200,
            "median_ring_span_seconds" => 129_600,
            "evicted_bytes" => 10_737_418_240
          }
        })

      %{server: server, proposal: proposal}
    end

    test "renders the open proposal with its evidence", %{conn: conn, user: user} do
      {:ok, _lv, html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

      assert html =~ "Sizing proposes growing the disk claim from 8Gi to 16Gi."
      # The evidence reads as what the cache is doing and what it should be
      # doing instead, with no policy vocabulary an operator would have to
      # look up.
      assert html =~ "discarding work a median of 12.0 hours after it was written"
      assert html =~ "should keep everything for at least 1.0 days"
      assert html =~ "Seen on 14 consecutive days of measurements"
      assert html =~ "Apply proposal"
    end

    test "shows what sizing has decided, whatever became of it", %{conn: conn, user: user} do
      now = DateTime.truncate(DateTime.utc_now(), :second)

      Repo.insert!(%ClaimProposal{
        account_id: user.account.id,
        region: "us-east",
        direction: :grow,
        current_claim_size: "8Gi",
        recommended_claim_size: "16Gi",
        evidence: %{"median_shed_age_seconds" => 1_800, "retention_floor_seconds" => 259_200},
        status: :applied,
        resolved_by: "automatic",
        resolved_at: now
      })

      Repo.insert!(%ClaimProposal{
        account_id: user.account.id,
        region: "us-east",
        direction: :shrink,
        current_claim_size: "32Gi",
        recommended_claim_size: "16Gi",
        evidence: %{"max_occupancy_percent" => 25},
        status: :dismissed,
        resolved_by: "ops@tuist.dev",
        resolved_at: now
      })

      {:ok, _lv, html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

      assert html =~ "8Gi → 16Gi"
      assert html =~ "32Gi → 16Gi"
      assert html =~ "peaked at 25% of its disk"

      # The outcome is a status token; who resolved it is its own column, and
      # sizing acting on its own reads as a name rather than an internal one.
      assert html =~ "applied"
      assert html =~ "dismissed"
      assert html =~ "Sizing"
      assert html =~ "ops@tuist.dev"
      refute html =~ "applied automatically"
    end

    test "says so when there is more history than it shows", %{conn: conn, user: user} do
      now = DateTime.truncate(DateTime.utc_now(), :second)

      for index <- 1..7 do
        Repo.insert!(%Tuist.Kura.ClaimProposal{
          account_id: user.account.id,
          region: "us-east",
          direction: :grow,
          current_claim_size: "8Gi",
          recommended_claim_size: "16Gi",
          evidence: %{"median_shed_age_seconds" => 1_800, "retention_floor_seconds" => 259_200},
          status: :applied,
          resolved_by: "automatic",
          resolved_at: DateTime.add(now, -index * 3600, :second),
          inserted_at: DateTime.add(now, -index * 3600, :second)
        })
      end

      {:ok, _lv, html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

      # Seven here plus the open proposal the setup creates.
      assert html =~ "the 5 most recent of 8"
    end

    test "applying the proposal writes the sized claim and re-pins the instance", %{
      conn: conn,
      user: user,
      server: server,
      proposal: proposal
    } do
      {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

      html = lv |> element("button", "Apply proposal") |> render_click()

      assert html =~ "Kura disk claim raised to 16Gi"
      assert Kura.sized_storage_claim(user.account) == "16Gi"
      assert Repo.get!(Server, server.id).storage_claim_size == "16Gi"
      assert Repo.get!(ClaimProposal, proposal.id).status == :applied
      refute has_element?(lv, "button", "Apply proposal")
    end

    test "dismissing the proposal leaves the claim alone", %{
      conn: conn,
      user: user,
      server: server,
      proposal: proposal
    } do
      {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

      lv |> element("button", "Dismiss") |> render_click()

      assert Kura.sized_storage_claim(user.account) == nil
      assert Repo.get!(Server, server.id).storage_claim_size == "8Gi"
      assert Repo.get!(ClaimProposal, proposal.id).status == :dismissed
      refute has_element?(lv, "button", "Dismiss")
    end
  end
end
