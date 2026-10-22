defmodule TuistWeb.Components.BuildMetadataTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias TuistWeb.Components.BuildMetadata

  test "each entry is rendered once, with unknown and invalid observations kept raw" do
    html =
      render_component(&BuildMetadata.build_metadata/1,
        values: %{
          "tuist.cpu.available_processors" => "28",
          "tuist.jvm.max_heap_bytes" => "1073741824",
          "tuist.gradle.max_workers" => "unknown-workers",
          "future.key" => "<script>untrusted</script>"
        }
      )

    assert html =~ "Infrastructure and runner"
    assert html =~ "Available logical processors"
    assert html =~ "Maximum JVM heap"
    assert html =~ "tuist.gradle.max_workers"
    assert html =~ "&lt;script&gt;untrusted&lt;/script&gt;"
    refute html =~ "<script>"
    text = html |> Floki.parse_fragment!() |> Floki.text()
    assert length(Regex.scan(~r/unknown-workers/, text)) == 1
    assert length(Regex.scan(~r/future.key/, text)) == 1
  end

  test "legacy empty maps render neither metadata section" do
    html = render_component(&BuildMetadata.build_metadata/1, values: %{})
    refute html =~ "custom-metadata-section"
    refute html =~ "build-environment-table"
  end
end
