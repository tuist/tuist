defmodule Tuist.Utilities.ByteFormatterTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Utilities.ByteFormatter

  describe "format_bytes/1" do
    test "formats bytes when 2 bytes" do
      assert "2 B" == ByteFormatter.format_bytes(2)
    end

    test "formats bytes when 1024 bytes" do
      assert "1.0 KB" == ByteFormatter.format_bytes(1024)
    end

    test "formats bytes when 1_000_000 bytes" do
      assert "1.0 MB" == ByteFormatter.format_bytes(1_000_000)
    end

    test "formats bytes when 1_000_000_000 bytes" do
      assert "1.0 GB" == ByteFormatter.format_bytes(1_000_000_000)
    end
  end
end
