defmodule Tuist.Processor.ZipExtractorTest do
  use ExUnit.Case, async: true

  alias Tuist.Processor.ZipExtractor

  @limits [max_bytes: 1024 * 1024, max_entries: 10]

  # A megabyte of zeros deflates to about a kilobyte.
  @zeros :binary.copy(<<0>>, 1024 * 1024)

  @moduletag :tmp_dir

  test "extracts stored, deflated and nested entries", %{tmp_dir: tmp_dir} do
    archive =
      zip(tmp_dir, [
        {~c"Test.xcresult/", ""},
        {~c"Test.xcresult/Info.plist", "plist"},
        {~c"Test.xcresult/Data/data.0~abc", :binary.copy("object ", 1000)},
        {~c"empty", ""}
      ])

    destination = Path.join(tmp_dir, "out")

    assert :ok = ZipExtractor.extract(archive, destination, @limits)
    assert File.read!(Path.join(destination, "Test.xcresult/Info.plist")) == "plist"
    assert File.read!(Path.join(destination, "Test.xcresult/Data/data.0~abc")) == :binary.copy("object ", 1000)
    assert File.read!(Path.join(destination, "empty")) == ""
  end

  test "extracts an archive exactly at both limits", %{tmp_dir: tmp_dir} do
    entries = [{~c"zeros", @zeros} | for(i <- 1..9, do: {~c"file#{i}", ""})]

    assert :ok = ZipExtractor.extract(zip(tmp_dir, entries), Path.join(tmp_dir, "out"), @limits)
  end

  test "rejects an archive that declares more bytes than the limit before writing anything", %{tmp_dir: tmp_dir} do
    archive = zip(tmp_dir, [{~c"zeros", @zeros <> <<0>>}])
    destination = Path.join(tmp_dir, "out")

    assert File.stat!(archive).size < 10 * 1024
    assert {:error, :archive_too_large} = ZipExtractor.extract(archive, destination, @limits)
    refute File.exists?(destination)
  end

  test "rejects an archive with more entries than the limit", %{tmp_dir: tmp_dir} do
    archive = zip(tmp_dir, for(i <- 1..11, do: {~c"file#{i}", ""}))

    assert {:error, :archive_too_large} = ZipExtractor.extract(archive, Path.join(tmp_dir, "out"), @limits)
  end

  # `:zip.unzip/2` writes the whole megabyte here: it never compares what it
  # inflates with the size the archive declares.
  test "stops an entry that inflates past the size it declares", %{tmp_dir: tmp_dir} do
    archive = tmp_dir |> zip([{~c"zeros", @zeros}]) |> understate_size(1024)
    destination = Path.join(tmp_dir, "out")

    assert {:error, :archive_too_large} = ZipExtractor.extract(archive, destination, @limits)
    assert File.stat!(Path.join(destination, "zeros")).size <= 1024
  end

  # Each record would write the same compressed data again under its own name.
  test "rejects central directory records that share an entry's data", %{tmp_dir: tmp_dir} do
    archive = tmp_dir |> zip([{~c"zero0", :binary.copy(<<0>>, 1024)}]) |> duplicate_record(~c"zero1")
    destination = Path.join(tmp_dir, "out")

    assert {:error, :bad_central_directory} = ZipExtractor.extract(archive, destination, @limits)
    refute File.exists?(destination)
  end

  test "rejects an entry whose content does not match its checksum", %{tmp_dir: tmp_dir} do
    archive = zip(tmp_dir, [{~c"log", "original activity log"}], [{:compress, []}])
    File.write!(archive, :binary.replace(File.read!(archive), "original", "modified"))

    assert {:error, {~c"log", :bad_crc}} = ZipExtractor.extract(archive, Path.join(tmp_dir, "out"), @limits)
  end

  test "rejects an entry that points outside the destination", %{tmp_dir: tmp_dir} do
    archive = zip(tmp_dir, [{~c"../escaped", "content"}])
    destination = Path.join(tmp_dir, "out")

    assert {:error, {:unsafe_entry_name, "../escaped"}} = ZipExtractor.extract(archive, destination, @limits)
    refute File.exists?(Path.join(tmp_dir, "escaped"))
  end

  test "passes through the reasons :zip gives for a malformed archive", %{tmp_dir: tmp_dir} do
    archive = zip(tmp_dir, [{~c"log", "content"}])
    content = File.read!(archive)
    File.write!(archive, binary_part(content, 0, byte_size(content) - 22))

    assert {:error, :bad_eocd} = ZipExtractor.extract(archive, Path.join(tmp_dir, "out"), @limits)
  end

  defp zip(tmp_dir, entries, options \\ []) do
    path = Path.join(tmp_dir, "archive-#{System.unique_integer([:positive])}.zip")
    {:ok, _} = :zip.create(~c"#{path}", entries, options)
    path
  end

  # Rewrites the uncompressed size a single-entry archive declares in its local
  # file header and its central directory, leaving the compressed data intact.
  defp understate_size(path, size) do
    content = File.read!(path)
    {local, _} = :binary.match(content, <<0x04034B50::32-little>>)
    {central, _} = :binary.match(content, <<0x02014B50::32-little>>)

    content =
      content
      |> replace_uint32(local + 22, size)
      |> replace_uint32(central + 24, size)

    File.write!(path, content)
    path
  end

  # Appends a second central directory record for a single-entry archive's
  # only entry, renamed to `name` (same length), pointing at the same data.
  defp duplicate_record(path, name) do
    content = File.read!(path)
    {central, _} = :binary.match(content, <<0x02014B50::32-little>>)
    eocd = byte_size(content) - 22
    name_length = length(name)

    <<local::binary-size(^central), record::binary-size(^eocd - ^central), _eocd::binary>> = content
    <<fixed::binary-size(46), original_name::binary-size(^name_length), rest::binary>> = record
    5 = byte_size(original_name)
    records = record <> fixed <> List.to_string(name) <> rest

    File.write!(
      path,
      local <>
        records <>
        <<0x06054B50::32-little, 0::16, 0::16, 2::16-little, 2::16-little, byte_size(records)::32-little,
          central::32-little, 0::16>>
    )

    path
  end

  defp replace_uint32(binary, offset, value) do
    <<before::binary-size(^offset), _::32, rest::binary>> = binary
    <<before::binary, value::32-little, rest::binary>>
  end
end
