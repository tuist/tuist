defmodule TuistWeb.Components.BuildHealthTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Phoenix.LiveView.AsyncResult
  alias TuistWeb.Components.BuildHealth

  test "failure category filter uses the same values and labels as the column" do
    filter = BuildHealth.category_filter()
    assert filter.field == :failure_category
    assert filter.options == ["verification", "infrastructure_tooling", "unknown"]
    assert BuildHealth.category_label("verification") == "Verification"
    assert BuildHealth.category_label("infrastructure_tooling") == "Infrastructure / tooling"
    assert BuildHealth.category_label("unknown") == "Unclassified"
    assert BuildHealth.category_label("") == "—"
  end

  test "missing and zero cache savings remain distinct, and coverage includes zero reports" do
    missing =
      render_component(&BuildHealth.cache_card/1,
        health:
          AsyncResult.ok(%{totals: %{"cache_work_avoided" => nil, "cache_work_avoided_samples" => 0, "builds" => 4}})
      )

    assert missing =~ "Not reported"
    assert missing =~ "0 of 4 builds"

    zero =
      render_component(&BuildHealth.cache_card/1,
        health: AsyncResult.ok(%{totals: %{"cache_work_avoided" => 0, "cache_work_avoided_samples" => 1, "builds" => 4}})
      )

    refute zero =~ "Not reported"
    assert zero =~ "1 of 4 builds"
    assert zero =~ "not elapsed build time saved"
  end

  test "loading and failure states never masquerade as no failures or zero cache savings" do
    for health <- [AsyncResult.loading(), AsyncResult.failed(AsyncResult.loading(), {:exit, :timeout})] do
      cache = render_component(&BuildHealth.cache_card/1, health: health)
      refute cache =~ "0 of"
      refute cache =~ "Not reported"
    end
  end
end
