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
    environment = render_component(&BuildMetadata.environment_metadata/1, values: values)

    assert environment =~ "Build environment"
    assert environment =~ "Available logical processors"
    assert environment =~ "Maximum JVM heap"
    refute environment =~ "unknown-workers"
    refute environment =~ "future.key"
    refute custom =~ "Available logical processors"
    assert custom =~ "tuist.gradle.max_workers"
    assert custom =~ "&lt;script&gt;untrusted&lt;/script&gt;"
    refute custom =~ "<script>"
    text = (custom <> environment) |> Floki.parse_fragment!() |> Floki.text()
    assert length(Regex.scan(~r/unknown-workers/, text)) == 1
    assert length(Regex.scan(~r/future.key/, text)) == 1
  end

  test "build environment is a separate Noora card collapsed before JavaScript mounts" do
    html =
      render_component(&BuildMetadata.environment_metadata/1,
        values: %{"tuist.cpu.available_processors" => "28"}
      )

    document = Floki.parse_fragment!(html)

    assert [_] = Floki.find(document, "#build-environment #build-environment-toggle[phx-click]")
    assert [_] = Floki.find(document, "#build-environment > .noora-card[data-state=closed]")

    assert [_] =
             Floki.find(
               document,
               "button[data-part=trigger][aria-label='Build environment'][aria-expanded=false][aria-controls=build-environment-content]"
             )

    assert [_] = Floki.find(document, "#build-environment-content.noora-card__section[hidden]")
    refute html =~ "custom-metadata-table"
  end

  test "custom metadata remains outside the environment disclosure" do
    html = render_component(&BuildMetadata.build_metadata/1, values: %{"team" => "mobile"})

    assert html =~ "Custom metadata"
    assert html =~ "custom-metadata-table"
    assert html =~ "mobile"
    refute html =~ "build-environment-toggle"
  end

  test "environment is omitted when only custom or invalid observations were reported" do
    for values <- [%{"team" => "mobile"}, %{"tuist.cpu.available_processors" => "unknown"}] do
      html = render_component(&BuildMetadata.environment_metadata/1, values: values)
      assert String.trim(html) == ""
    end
  end

  test "existing fields show the environment even without new observations" do
    html =
      render_component(&BuildMetadata.environment_metadata/1,
        fields: [{"Gradle Version", "9.2.1"}, {"Java Version", "21.0.7"}]
      )

    document = Floki.parse_fragment!(html)
    assert [_] = Floki.find(document, "#build-environment-content[hidden]")
    assert html =~ "Gradle Version"
    assert html =~ "9.2.1"
    assert html =~ "Java Version"
    assert html =~ "21.0.7"
    refute html =~ "custom-metadata-table"
  end

  test "existing fields and observations are rendered together without rewriting metadata" do
    values = %{"tuist.jvm.vendor" => "Eclipse Adoptium", "team" => "mobile"}

    html =
      render_component(&BuildMetadata.environment_metadata/1,
        fields: [{"Java Version", "21.0.7"}],
        values: values
      )

    document = Floki.parse_fragment!(html)
    rows = Floki.find(document, "#build-environment-table tbody tr")
    assert length(rows) == 2
    assert Floki.text(hd(rows)) =~ "Java Version"
    assert Floki.text(List.last(rows)) =~ "Eclipse Adoptium"
    refute html =~ "mobile"
  end

  test "missing existing fields are omitted rather than displaying an empty environment" do
    html =
      render_component(&BuildMetadata.environment_metadata/1,
        fields: [{"Java Version", nil}, {"Gradle Version", ""}, {"Rust version", "  "}]
      )

    assert String.trim(html) == ""
  end

  test "existing fields and observations remain escaped while ordinary metadata retains safe links" do
    values = %{
      "tuist.ci.runner_name" => "<script>untrusted</script>",
      "tuist.ci.job" => "https://example.com/job",
      "build-link" => "https://example.com/build",
      "unsafe-link" => "javascript:alert(1)"
    }

    environment =
      render_component(&BuildMetadata.environment_metadata/1,
        values: values,
        fields: [{"Once version", "<script>version</script>"}]
      )

    custom = render_component(&BuildMetadata.build_metadata/1, values: values)

    assert environment =~ "&lt;script&gt;untrusted&lt;/script&gt;"
    assert environment =~ "&lt;script&gt;version&lt;/script&gt;"
    assert environment =~ "https://example.com/job"
    assert [] == environment |> Floki.parse_fragment!() |> Floki.find("a, script")

    assert ["https://example.com/build"] ==
             custom |> Floki.parse_fragment!() |> Floki.find("a") |> Floki.attribute("href")
  end

  test "legacy empty maps without existing fields render neither metadata section" do
    for component <- [&BuildMetadata.build_metadata/1, &BuildMetadata.environment_metadata/1] do
      assert component |> render_component(values: %{}) |> String.trim() == ""
    end
  end
end
