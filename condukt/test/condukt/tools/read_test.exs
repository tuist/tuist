defmodule Condukt.Tools.ReadTest do
  use ExUnit.Case, async: true

  alias Condukt.Sandbox
  alias Condukt.Tools.Read

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    {:ok, sandbox} = Sandbox.new(Sandbox.Local, cwd: tmp_dir)
    %{context: %{sandbox: sandbox, opts: []}}
  end

  test "reads file contents", %{tmp_dir: tmp_dir, context: context} do
    File.write!(Path.join(tmp_dir, "test.txt"), "Hello, World!")

    {:ok, result} = Read.call(%{"path" => "test.txt"}, context)

    assert is_binary(result)
    assert result == "Hello, World!"
  end

  test "reads with offset and limit", %{tmp_dir: tmp_dir, context: context} do
    File.write!(Path.join(tmp_dir, "lines.txt"), "line1\nline2\nline3\nline4\nline5")

    {:ok, result} = Read.call(%{"path" => "lines.txt", "offset" => 2, "limit" => 2}, context)

    assert String.contains?(result, "line2")
    assert String.contains?(result, "line3")
    refute String.contains?(result, "line1")
    refute String.contains?(result, "line4")
  end

  test "returns error for missing file", %{context: context} do
    {:error, error} = Read.call(%{"path" => "missing.txt"}, context)

    assert String.contains?(error, "not found")
  end

  test "returns error for directory", %{context: context} do
    {:error, error} = Read.call(%{"path" => "."}, context)

    assert String.contains?(error, "directory")
  end

  test "returns image content for image files", %{tmp_dir: tmp_dir, context: context} do
    path = Path.join(tmp_dir, "pixel.png")

    png_data =
      Base.decode64!("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+X2Z0AAAAASUVORK5CYII=")

    File.write!(path, png_data)

    {:ok, result} = Read.call(%{"path" => "pixel.png"}, context)

    assert %{
             type: :image,
             media_type: "image/png",
             data: encoded_data
           } = result

    assert Base.decode64!(encoded_data) == png_data
  end

  test "recognizes images by content, not extension", %{tmp_dir: tmp_dir, context: context} do
    images = [
      {"photo.dat", <<0xFF, 0xD8, 0xFF, 0xE0>>, "image/jpeg"},
      {"anim.bin", "GIF89a....", "image/gif"},
      {"pic", "RIFF\0\0\0\0WEBPVP8 ", "image/webp"}
    ]

    for {filename, bytes, media_type} <- images do
      File.write!(Path.join(tmp_dir, filename), bytes)
      assert {:ok, %{type: :image, media_type: ^media_type}} = Read.call(%{"path" => filename}, context)
    end

    File.write!(Path.join(tmp_dir, "fake.png"), "not an image")
    assert {:ok, "not an image"} = Read.call(%{"path" => "fake.png"}, context)
  end

  test "names the offset to continue from after a limit", %{tmp_dir: tmp_dir, context: context} do
    File.write!(Path.join(tmp_dir, "lines.txt"), "1\n2\n3\n4\n5")

    assert {:ok, "2\n3\n\n[2 more lines in file. Use offset=4 to continue.]"} =
             Read.call(%{"path" => "lines.txt", "offset" => 2, "limit" => 2}, context)

    assert {:ok, "4\n5"} = Read.call(%{"path" => "lines.txt", "offset" => 4, "limit" => 5}, context)

    assert {:error, "Offset 9 is beyond end of file (5 lines total)"} =
             Read.call(%{"path" => "lines.txt", "offset" => 9}, context)
  end

  test "cuts long files at 2000 lines with a continuation notice", %{tmp_dir: tmp_dir, context: context} do
    File.write!(Path.join(tmp_dir, "big.txt"), Enum.map_join(1..2500, "\n", &Integer.to_string/1))

    assert {:ok, result} = Read.call(%{"path" => "big.txt"}, context)
    assert String.starts_with?(result, "1\n2\n")
    assert String.ends_with?(result, "\n2000\n\n[Showing lines 1-2000 of 2500. Use offset=2001 to continue.]")
  end

  test "cuts at 50KB and points at bash for a line over the limit", %{tmp_dir: tmp_dir, context: context} do
    line = String.duplicate("y", 1000)
    File.write!(Path.join(tmp_dir, "wide.txt"), Enum.map_join(1..60, "\n", fn _ -> line end))

    assert {:ok, result} = Read.call(%{"path" => "wide.txt"}, context)
    assert String.ends_with?(result, "\n\n[Showing lines 1-51 of 60 (50.0KB limit). Use offset=52 to continue.]")

    File.write!(Path.join(tmp_dir, "huge.txt"), "short\n" <> String.duplicate("z", 60_000))

    assert {:ok, "[Line 2 is 58.6KB, exceeds 50.0KB limit. Use bash: sed -n '2p' huge.txt | head -c 51200]"} =
             Read.call(%{"path" => "huge.txt", "offset" => 2}, context)
  end

  test "raises a clear error if context.sandbox is missing", %{tmp_dir: tmp_dir} do
    File.write!(Path.join(tmp_dir, "test.txt"), "x")

    assert_raise ArgumentError, ~r/requires context\.sandbox/, fn ->
      Read.call(%{"path" => "test.txt"}, %{cwd: tmp_dir, opts: []})
    end
  end
end
