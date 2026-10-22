defmodule TuistWeb.Components.BuildMetadataTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias TuistWeb.Components.BuildMetadata

  test "each entry is rendered once, with unknown and invalid observations kept raw" do
    values = %{
      "tuist.cpu.available_processors" => "28",
      "tuist.jvm.max_heap_bytes" => "1073741824",
      "tuist.gradle.max_workers" => "unknown-workers",
      "future.key" => "<script>untrusted</script>"
    }

    custom = render_component(&BuildMetadata.build_metadata/1, values: values)
    infrastructure = render_component(&BuildMetadata.infrastructure_metadata/1, values: values)

    assert infrastructure =~ "Infrastructure and runner"
    assert infrastructure =~ "Available logical processors"
    assert infrastructure =~ "Maximum JVM heap"
    refute infrastructure =~ "unknown-workers"
    refute infrastructure =~ "future.key"
    refute custom =~ "Available logical processors"
    assert custom =~ "tuist.gradle.max_workers"
    assert custom =~ "&lt;script&gt;untrusted&lt;/script&gt;"
    refute custom =~ "<script>"
    text = (custom <> infrastructure) |> Floki.parse_fragment!() |> Floki.text()
    assert length(Regex.scan(~r/unknown-workers/, text)) == 1
    assert length(Regex.scan(~r/future.key/, text)) == 1
  end

  test "infrastructure is a separate Noora card collapsed before JavaScript mounts" do
    html =
      render_component(&BuildMetadata.infrastructure_metadata/1,
        values: %{"tuist.cpu.available_processors" => "28"}
      )

    document = Floki.parse_fragment!(html)

    assert [_] = Floki.find(document, "#build-environment #build-environment-toggle[phx-click]")
    assert [_] = Floki.find(document, "#build-environment > .noora-card[data-state=closed]")

    assert [_] =
             Floki.find(
               document,
               "button[data-part=trigger][aria-expanded=false][aria-controls=build-environment-content]"
             )

    assert [_] = Floki.find(document, "#build-environment-content.noora-card__section[hidden]")
    refute html =~ "custom-metadata-table"
  end

  test "custom metadata remains outside the infrastructure disclosure" do
    html = render_component(&BuildMetadata.build_metadata/1, values: %{"team" => "mobile"})

    assert html =~ "Custom metadata"
    assert html =~ "custom-metadata-table"
    assert html =~ "mobile"
    refute html =~ "build-environment-toggle"
    refute html =~ "Infrastructure and runner"
  end

  test "infrastructure is omitted when only custom or invalid observations were reported" do
    for values <- [%{"team" => "mobile"}, %{"tuist.cpu.available_processors" => "unknown"}] do
      html = render_component(&BuildMetadata.infrastructure_metadata/1, values: values)
      assert String.trim(html) == ""
    end
  end

  test "observations remain escaped text while ordinary metadata retains safe links" do
    values = %{
      "tuist.ci.runner_name" => "<script>untrusted</script>",
      "tuist.ci.job" => "https://example.com/job",
      "build-link" => "https://example.com/build",
      "unsafe-link" => "javascript:alert(1)"
    }

    infrastructure = render_component(&BuildMetadata.infrastructure_metadata/1, values: values)
    custom = render_component(&BuildMetadata.build_metadata/1, values: values)

    assert infrastructure =~ "&lt;script&gt;untrusted&lt;/script&gt;"
    assert infrastructure =~ "https://example.com/job"
    assert [] == infrastructure |> Floki.parse_fragment!() |> Floki.find("a, script")

    assert ["https://example.com/build"] ==
             custom |> Floki.parse_fragment!() |> Floki.find("a") |> Floki.attribute("href")
  end

  test "legacy empty maps render neither metadata section" do
    for component <- [&BuildMetadata.build_metadata/1, &BuildMetadata.infrastructure_metadata/1] do
      assert component |> render_component(values: %{}) |> String.trim() == ""
    end
  end
end
