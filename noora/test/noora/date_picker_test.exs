defmodule Noora.DatePickerTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Noora.DatePicker

  defp trigger_label(period) do
    html =
      render_component(&DatePicker.date_picker/1, %{
        id: "date-picker",
        selected_preset: "custom",
        period: period,
        presets: [%{id: "custom", label: "Custom"}]
      })

    [_, label] = Regex.run(~r{data-part="trigger".*?<span>([^<]*)</span>}s, html)
    String.trim(label)
  end

  test "renders the trigger as a secondary Noora button" do
    html =
      render_component(&DatePicker.date_picker/1, %{
        id: "date-picker",
        disabled: true,
        presets: [%{id: "custom", label: "Custom"}]
      })

    [trigger] = Regex.run(~r{<button[^>]*data-part="trigger"[^>]*>}, html)
    assert trigger =~ ~s(class="noora-button")
    assert trigger =~ ~s(data-variant="secondary")
    assert trigger =~ "disabled"
  end

  test "leaves out the typed-range field when typed ranges are off" do
    render = fn assigns ->
      render_component(
        &DatePicker.date_picker/1,
        Map.merge(%{id: "date-picker", presets: [%{id: "last-7-days", label: "Last 7 days"}]}, assigns)
      )
    end

    assert render.(%{}) =~ ~s(data-part="range-input")

    html = render.(%{typed_ranges: false})
    refute html =~ ~s(data-part="range-input")
    refute html =~ ~s(data-part="suggestions")
    assert html =~ ~s(data-preset-id="last-7-days")
  end

  test "labels a typed rolling range that no preset has" do
    label = fn preset ->
      html =
        render_component(&DatePicker.date_picker/1, %{
          id: "date-picker",
          selected_preset: preset,
          presets: [%{id: "last-7-days", label: "Past week"}]
        })

      [_, label] = Regex.run(~r{data-part="trigger".*?<span>([^<]*)</span>}s, html)
      String.trim(label)
    end

    assert label.("last-10-days") == "Last 10 days"
    assert label.("last-1-month") == "Last month"
    # A preset with the same id keeps its own label.
    assert label.("last-7-days") == "Past week"
  end

  test "labels a custom range in words, naming the month and year only where they change" do
    assert trigger_label({~U[2026-09-01 00:00:00Z], ~U[2026-09-30 23:59:59Z]}) == "Sep 1 - 30, 2026"
    assert trigger_label({~U[2028-01-31 00:00:00Z], ~U[2028-03-02 23:59:59Z]}) == "Jan 31 - Mar 2, 2028"

    assert trigger_label({~U[2025-12-28 00:00:00Z], ~U[2026-01-03 23:59:59Z]}) ==
             "Dec 28, 2025 - Jan 3, 2026"
  end
end
