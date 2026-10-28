defmodule Tuist.Accounts.AirUsageEmailTest do
  use ExUnit.Case, async: true
  use Mimic
  use Bamboo.Test

  alias Tuist.Accounts.UserNotifier
  alias Tuist.Environment

  setup do
    stub(Environment, :app_url, fn _ -> "https://tuist.dev/acme/billing" end)
    stub(Environment, :email_icon_url, fn -> "https://tuist.dev/images/tuist_email.png" end)
    stub(Environment, :mailing_from_address, fn -> "noreply@tuist.dev" end)
    stub(Environment, :mailing_reply_to_address, fn -> "contact@tuist.dev" end)
    :ok
  end

  test "80% email includes usage, reset date, upgrade link, and plain text" do
    email = UserNotifier.air_usage_email(%{email: "admin@example.com"}, %{name: "acme"}, notification(80))
    assert email.subject == "acme has reached 80% of its Air limit"
    assert email.html_body =~ "You're approaching your Air limit"
    assert email.html_body =~ "800,000 of 1,000,000 cache requests used"
    assert email.html_body =~ "October 1, 2026 (UTC)"
    assert email.html_body =~ ~s(href="https://tuist.dev/acme/billing")
    assert email.text_body =~ "800,000 of 1,000,000 cache requests used (80%)"
    assert email.text_body =~ "https://tuist.dev/acme/billing"
    assert email.headers["Reply-To"] == "contact@tuist.dev"
  end

  test "100% email explains the interruption and is delivered only to the recipient" do
    assert {:ok, email} =
             UserNotifier.deliver_air_usage_notification(
               %{email: "admin@example.com"},
               %{name: "acme"},
               notification(100)
             )

    assert email.subject == "acme has reached 100% of its Air limit"
    assert email.html_body =~ "You've reached your Air limit"
    assert email.html_body =~ "Remote cache access is paused"
    assert email.text_body =~ "1,000,000 of 1,000,000 cache requests used (100%)"
    assert email.to == [nil: "admin@example.com"]
    assert email.cc == []
    assert email.bcc == []
    assert_delivered_email(email)
  end

  test "escapes account names in HTML and caps the progress bar for overshoots" do
    email =
      UserNotifier.air_usage_email(%{email: "admin@example.com"}, %{name: "<acme>"}, %{
        notification(100)
        | usage: 1_200_000
      })

    assert email.html_body =~ "&lt;acme&gt;"
    refute email.html_body =~ "<acme>"
    assert email.subject == "<acme> has reached 120% of its Air limit"
    assert email.text_body =~ "1,200,000 of 1,000,000 cache requests used (120%)"
    assert email.html_body =~ ">120%</p>"
    assert email.html_body =~ "1,200,000 of 1,000,000 cache requests used"
    assert email.html_body =~ ~s(width="100%")
    refute email.html_body =~ ~s(width="120%")
  end

  test "cache emails show the cache allowance the account reached" do
    egress =
      80
      |> notification()
      |> Map.merge(%{metric: :cache_egress_megabytes, usage: 82_300, limit: 100_000})

    requests =
      100
      |> notification()
      |> Map.merge(%{metric: :cache_requests, usage: 1_250_000, limit: 1_000_000})

    egress_email = UserNotifier.air_usage_email(%{email: "admin@example.com"}, %{name: "acme"}, egress)
    requests_email = UserNotifier.air_usage_email(%{email: "admin@example.com"}, %{name: "acme"}, requests)

    assert egress_email.subject == "acme has reached 82% of its Air limit"
    assert egress_email.text_body =~ "82.3 GB of 100.0 GB of cache egress used"
    assert requests_email.text_body =~ "1,250,000 of 1,000,000 cache requests used"
    assert requests_email.html_body =~ "Remote cache access is paused"
    refute egress_email.html_body =~ "remote cache hits"
  end

  test "runner emails identify the runner allowance and explain what pauses" do
    for threshold <- [80, 100] do
      notification =
        threshold |> notification() |> Map.put(:metric, :runner_minutes) |> Map.merge(%{usage: threshold, limit: 100})

      email = UserNotifier.air_usage_email(%{email: "admin@example.com"}, %{name: "acme"}, notification)

      assert email.subject == "acme has reached #{threshold}% of its Air runner limit"
      assert email.html_body =~ "#{threshold} of 100 baseline runner minutes used"
      assert email.html_body =~ "October 1, 2026 (UTC)"
      assert email.html_body =~ ~s(href="https://tuist.dev/acme/billing")
      assert email.text_body =~ "#{threshold} of 100 baseline runner minutes used"
      refute email.html_body =~ "remote cache hits"
      refute email.text_body =~ "Remote cache access is paused"

      if threshold == 100 do
        assert email.html_body =~ "New runner jobs are paused"
      else
        assert email.html_body =~ "You're nearing your Air runner limit"
      end
    end
  end

  test "uses the actual percentage in the subject and both email bodies" do
    email =
      UserNotifier.air_usage_email(%{email: "admin@example.com"}, %{name: "acme"}, %{notification(80) | usage: 950_000})

    assert email.subject == "acme has reached 95% of its Air limit"
    assert email.html_body =~ ">95%</p>"
    assert email.text_body =~ "950,000 of 1,000,000 cache requests used (95%)"
  end

  test "uses the recipient locale for copy and month names without leaking it to later deliveries" do
    previous_locale = Gettext.get_locale(TuistWeb.Gettext)

    expect(Environment, :app_url, fn [path: "/acme/billing"] ->
      assert Gettext.get_locale(TuistWeb.Gettext) == "es"
      "https://tuist.dev/acme/billing"
    end)

    email =
      UserNotifier.air_usage_email(
        %{email: "admin@example.com", preferred_locale: "es"},
        %{name: "acme"},
        notification(80)
      )

    assert email.html_body =~ ~s(<html lang="es">)
    assert email.html_body =~ "Octubre 1, 2026"
    assert email.text_body =~ "Octubre 1, 2026"
    assert Gettext.get_locale(TuistWeb.Gettext) == previous_locale
  end

  test "uses an unambiguous numeric date when month translations are unavailable" do
    email =
      UserNotifier.air_usage_email(
        %{email: "admin@example.com", preferred_locale: "ka"},
        %{name: "acme"},
        notification(80)
      )

    assert email.html_body =~ "2026-10-01"
    assert email.text_body =~ "2026-10-01"
  end

  defp notification(threshold) do
    %{
      metric: :cache_requests,
      threshold: threshold,
      usage: threshold * 10_000,
      limit: 1_000_000,
      period_start: ~U[2026-09-01 00:00:00Z]
    }
  end
end
