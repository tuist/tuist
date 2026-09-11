defmodule Tuist.Marketing.Changelog.EntryTest do
  use ExUnit.Case, async: true

  alias Tuist.Marketing.Changelog.Entry

  test "returns the first image source in an entry body" do
    entry =
      entry_with_body("""
      <p>First paragraph.</p>
      <img src="/marketing/images/changelog/first.png" alt="First image">
      <img src="/marketing/images/changelog/second.png" alt="Second image">
      """)

    assert Entry.image_source(entry) == "/marketing/images/changelog/first.png"
  end

  test "returns nil when an entry body has no images" do
    assert Entry.image_source(entry_with_body("<p>Only text.</p>")) == nil
  end

  defp entry_with_body(body) do
    %Entry{
      category: "Product",
      date: ~U[2026-08-21 00:00:00Z],
      title: "Entry title",
      body: body,
      id: "entry-id"
    }
  end
end
