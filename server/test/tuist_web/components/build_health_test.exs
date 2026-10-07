defmodule TuistWeb.Components.BuildHealthTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Phoenix.LiveView.AsyncResult
  alias TuistWeb.Components.BuildHealth

  test "failure links point at each toolchain's detail page and missing evidence stays unclassified" do
    for {system, path} <- [
          {"gradle", "builds/build-runs"},
          {"xcode", "builds/build-runs"},
          {"bazel", "builds/invocations"},
          {"once", "once/runs"}
        ] do
      html =
        render_component(&BuildHealth.failure_card/1,
          account: %{name: "team"},
          project: %{name: "app"},
          health:
            AsyncResult.ok(%{
              categories: [%{category: "unknown", builds: 1}],
              failures: [
                %{
                  id: "build-id",
                  build_system: system,
                  requested_tasks: ["compile"],
                  failure_category: "unknown",
                  git_branch: "main",
                  duration_ms: 0
                }
              ]
            })
        )

      assert html =~ "/team/app/#{path}/build-id"
      assert html =~ "Unclassified"
      assert html =~ ~s(id="failure-build-id")
      refute html =~ "Not reported"
    end
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
      html =
        render_component(&BuildHealth.failure_card/1, health: health, account: %{name: "team"}, project: %{name: "app"})

      refute html =~ "No failed builds"
      refute html =~ "build-failure-category-counts"
      cache = render_component(&BuildHealth.cache_card/1, health: health)
      refute cache =~ "0 of"
      refute cache =~ "Not reported"
    end
  end

  test "builds without requested tasks keep a visible navigation label" do
    html =
      render_component(&BuildHealth.failure_card/1,
        account: %{name: "team"},
        project: %{name: "app"},
        health:
          AsyncResult.ok(%{
            categories: [],
            failures: [
              %{
                id: "id",
                build_system: "xcode",
                requested_tasks: [""],
                failure_category: "unknown",
                git_branch: "main",
                duration_ms: 0
              }
            ]
          })
      )

    assert html =~ "Not reported"
    assert html =~ "/team/app/builds/build-runs/id"
  end
end
