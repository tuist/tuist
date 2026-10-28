defmodule TuistEx.Analytics.TempDirTest do
  use ExUnit.Case, async: true

  alias TuistEx.Analytics.TempDir

  test "hands out a new private directory and removes it afterwards" do
    {first, mode} =
      TempDir.with_dir("tuist-ex-test", fn dir ->
        File.write!(Path.join(dir, "file"), "contents")
        {dir, File.stat!(dir).mode}
      end)

    second = TempDir.with_dir("tuist-ex-test", & &1)

    assert first != second
    assert Bitwise.band(mode, 0o777) == 0o700
    refute File.exists?(first)
    refute File.exists?(second)
  end
end
