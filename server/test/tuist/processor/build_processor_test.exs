defmodule Tuist.Processor.BuildProcessorTest do
  use ExUnit.Case, async: true

  alias Tuist.Processor.BuildProcessor

  @tag :tmp_dir
  test "returns {:error, :bad_zip} when the archive is not a valid zip", %{tmp_dir: tmp_dir} do
    zip_path = Path.join(tmp_dir, "corrupt.zip")
    File.write!(zip_path, "not a zip file")

    assert {:error, :bad_zip} = BuildProcessor.process_build(zip_path, false)
  end

  @tag :tmp_dir
  test "returns {:error, :bad_zip} when the archive is truncated", %{tmp_dir: tmp_dir} do
    zip_path = Path.join(tmp_dir, "empty.zip")
    File.write!(zip_path, "")

    assert {:error, :bad_zip} = BuildProcessor.process_build(zip_path, false)
  end
end
