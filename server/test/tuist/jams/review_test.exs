defmodule Tuist.Jams.ReviewTest do
  use ExUnit.Case, async: true

  alias Tuist.Jams.Review

  @base String.duplicate("a", 40)
  @jam "5e2bde92-bde1-4f74-a38f-f5b1e30b9933"

  test "server Git renders adds, edits, deletes, executable modes, symlinks and binary blobs" do
    before = %{
      "edit.txt" => {"100644", "old\n"},
      "delete.txt" => {"100644", "gone\n"},
      "script" => {"100644", "#!/bin/sh\n"},
      "keep.txt" => {"100644", "not fetched\n"}
    }

    after_files = %{
      "edit.txt" => {"100644", "new\n"},
      "nested/add.txt" => {"100644", "added\n"},
      "script" => {"100755", "#!/bin/sh\n"},
      "link" => {"120000", "edit.txt"},
      "binary" => {"100644", <<0, 255, 1, 2, 0>>},
      "keep.txt" => {"100644", "not fetched\n"}
    }

    {snapshot, objects, responses} = fixture(before, after_files)
    responses = Map.delete(responses, "/git/blobs/#{hash("blob", "not fetched\n")}")
    assert {:ok, patch} = Review.diff(snapshot, objects, fetch(responses))
    assert patch =~ "-old\n+new\n"
    assert patch =~ "deleted file mode 100644"
    assert patch =~ "new file mode 120000"
    assert patch =~ "old mode 100644\nnew mode 100755"
    assert patch =~ "diff --git a/nested/add.txt b/nested/add.txt"
    assert patch =~ "GIT binary patch"
    refute patch =~ "keep.txt"
  end

  test "fetches only the trusted base commit, recursive tree, and changed old blobs" do
    {snapshot, objects, responses} = fixture(%{"file" => {"100644", "old"}}, %{"file" => {"100644", "new"}})
    owner = self()

    fetch = fn path ->
      send(owner, {:fetched, path})
      {:ok, Map.fetch!(responses, path)}
    end

    assert {:ok, _} = Review.diff(snapshot, objects, fetch)
    assert_received {:fetched, "/git/commits/" <> @base}
    tree_path = "/git/trees/#{tree(%{"file" => {"100644", "old"}})}?recursive=1"
    blob_path = "/git/blobs/#{hash("blob", "old")}"
    assert_received {:fetched, ^tree_path}
    assert_received {:fetched, ^blob_path}
    refute_received {:fetched, _}
  end

  test "guest benign diff cannot hide malicious bytes, tree or head" do
    {snapshot, objects, responses} = fixture(%{}, %{"payload" => {"100644", "malicious\n"}})
    objects = Map.put(objects, "diff", "benign guest diff")
    assert {:ok, patch} = Review.diff(snapshot, objects, fetch(responses))
    assert patch =~ "+malicious"
    refute patch =~ "benign"

    assert_invalid(snapshot, Map.put(objects, "tree_sha", @base), responses)
    assert_invalid(%{snapshot | head_sha: @base}, objects, responses)
    assert_invalid(%{snapshot | jam_id: "different-jam"}, objects, responses)

    [entry] = objects["entries"]
    assert_invalid(snapshot, %{objects | "entries" => [%{entry | "content" => Base.encode64("benign")}]}, responses)
    assert_invalid(snapshot, %{objects | "entries" => []}, responses)
  end

  test "a database approval is reviewed with the same immutable snapshot contract" do
    {snapshot, objects, responses} = fixture(%{}, %{"file" => {"100644", "approved bytes\n"}})
    approval = struct!(Tuist.Jams.Approval, snapshot)
    assert {:ok, patch} = Review.diff(approval, objects, fetch(responses))
    assert patch =~ "+approved bytes"
  end

  test "canonical commit hash is independently checked by real Git" do
    {snapshot, objects, responses} = fixture(%{}, %{"file" => {"100644", "hello"}})
    identity = "Tuist Jams <jams@tuist.dev> 946684800 +0000"

    commit =
      "tree #{objects["tree_sha"]}\nparent #{@base}\nauthor #{identity}\ncommitter #{identity}\n\nTuist Jams #{@jam}\n"

    dir = temporary_directory()
    on_exit(fn -> File.rm_rf!(dir) end)
    path = Path.join(dir, "commit")
    File.write!(path, commit)
    assert {output, 0} = System.cmd("git", ["hash-object", "-t", "commit", "--", path], cd: dir)
    assert String.trim(output) == snapshot.head_sha
    assert {:ok, _} = Review.diff(snapshot, objects, fetch(responses))
  end

  test "Git byte ordering puts a tree after a dot-suffixed sibling" do
    before = %{"a/file" => {"100644", "old"}, "a.txt" => {"100644", "sibling"}}
    after_files = Map.put(before, "a/file", {"100644", "new"})
    {snapshot, objects, responses} = fixture(before, after_files)
    assert {:ok, patch} = Review.diff(snapshot, objects, fetch(responses))
    assert patch =~ "a/a/file b/a/file"
  end

  test "file-directory transitions are reviewed without fetching unchanged blobs" do
    for {before, after_files} <- [
          {%{"a" => {"100644", "old"}}, %{"a/file" => {"100644", "new"}}},
          {%{"a/file" => {"100644", "old"}}, %{"a" => {"100644", "new"}}}
        ] do
      {snapshot, objects, responses} = fixture(before, after_files)
      assert {:ok, patch} = Review.diff(snapshot, objects, fetch(responses))
      assert patch =~ "deleted file mode"
      assert patch =~ "new file mode"
    end
  end

  test "unchanged submodules are preserved without fetching commit/blob objects" do
    submodule = {"160000", String.duplicate("b", 40)}
    before = %{"vendor" => submodule, "file" => {"100644", "old"}}
    after_files = Map.put(before, "file", {"100644", "new"})
    {snapshot, objects, responses} = fixture(before, after_files)
    assert {:ok, patch} = Review.diff(snapshot, objects, fetch(responses))
    refute patch =~ "vendor"

    [entry] = objects["entries"]

    for path <- ["vendor", "vendor/child"] do
      assert_invalid(snapshot, %{objects | "entries" => [%{entry | "path" => path}]}, responses)
    end

    deletion = %{"path" => "vendor", "mode" => "100644", "type" => "blob", "sha" => nil}
    assert_invalid(snapshot, %{objects | "entries" => [deletion]}, responses)
  end

  test "rejects duplicate, unsafe, conflicting paths and unsupported modes/types" do
    {snapshot, objects, responses} = fixture(%{}, %{"file" => {"100644", "new"}})
    [entry] = objects["entries"]
    assert_invalid(snapshot, %{objects | "entries" => [entry, entry]}, responses)

    for path <- ["../escape", "/absolute", "a//b", "a/./b", ".git/config", "a/.GIT/config", "a\\b", "a\0b", ""] do
      assert_invalid(snapshot, %{objects | "entries" => [%{entry | "path" => path}]}, responses)
    end

    for mode <- ["160000", "040000", "100600", 100_644, nil] do
      assert_invalid(snapshot, %{objects | "entries" => [%{entry | "mode" => mode}]}, responses)
    end

    assert_invalid(snapshot, %{objects | "entries" => [%{entry | "type" => "tree"}]}, responses)
    assert_invalid(snapshot, %{objects | "entries" => [%{entry | "content" => "%%%"}]}, responses)
    assert_invalid(snapshot, %{objects | "entries" => [entry, %{entry | "path" => "file/child"}]}, responses)
  end

  test "rejects truncated, oversized, structurally invalid and forged trusted tree listings" do
    {snapshot, objects, responses} = fixture(%{"dir/file" => {"100644", "old"}}, %{"dir/file" => {"100644", "new"}})
    tree_path = Enum.find(Map.keys(responses), &String.starts_with?(&1, "/git/trees/"))
    body = responses[tree_path]
    [directory, file] = Enum.sort_by(body["tree"], & &1["path"])

    for invalid <- [
          %{body | "truncated" => true},
          Map.delete(body, "truncated"),
          %{body | "tree" => [file]},
          %{body | "tree" => [directory, file, file]},
          %{body | "tree" => [%{directory | "sha" => @base}, file]},
          %{body | "tree" => [directory, %{file | "path" => "../bad"}]},
          %{body | "tree" => [directory, %{file | "mode" => "100600"}]},
          %{body | "tree" => [directory, %{file | "type" => "commit"}]},
          %{body | "tree" => []},
          %{body | "tree" => List.duplicate(file, 50_001)},
          %{body | "sha" => @base}
        ] do
      assert_invalid(snapshot, objects, Map.put(responses, tree_path, invalid))
    end
  end

  test "limits exported count and total bytes before any upstream fetch" do
    {snapshot, objects, _responses} = fixture(%{}, %{"file" => {"100644", "new"}})
    fetch = fn _ -> flunk("invalid export must not fetch upstream") end
    [entry] = objects["entries"]

    assert {:error, :shipping_objects_invalid} =
             Review.diff(snapshot, %{objects | "entries" => List.duplicate(entry, 201)}, fetch)

    data = String.duplicate("x", 300_000)
    entry = %{entry | "sha" => hash("blob", data), "content" => Base.encode64(data)}
    oversized = %{objects | "entries" => [entry, %{entry | "path" => "second"}]}
    assert {:error, :shipping_objects_invalid} = Review.diff(snapshot, oversized, fetch)
  end

  test "rejects invalid, hash-mismatched and oversized old blobs" do
    {snapshot, objects, responses} = fixture(%{"file" => {"100644", "old"}}, %{"file" => {"100644", "new"}})
    path = "/git/blobs/#{hash("blob", "old")}"
    body = responses[path]

    for invalid <- [
          %{body | "content" => Base.encode64("lie")},
          %{body | "content" => "%%%"},
          %{body | "size" => 1_048_577},
          %{body | "size" => -1},
          %{body | "size" => 2},
          %{body | "sha" => @base},
          %{body | "encoding" => "utf-8"}
        ] do
      assert_invalid(snapshot, objects, Map.put(responses, path, invalid))
    end
  end

  test "old blobs have a total one MiB budget, not just an individual cap" do
    before = %{"one" => {"100644", String.duplicate("x", 600_000)}, "two" => {"100644", String.duplicate("y", 600_000)}}
    {snapshot, objects, responses} = fixture(before, %{})
    assert_invalid(snapshot, objects, responses)
  end

  test "rejects empty and over-limit patches instead of truncating approval text" do
    {snapshot, objects, responses} = fixture(%{}, %{})
    assert {:error, :shipping_diff_empty_or_too_large} = Review.diff(snapshot, objects, fetch(responses))

    {snapshot, objects, responses} = fixture(%{}, %{"file" => {"100644", String.duplicate("long line\n", 20_000)}})
    assert {:error, :shipping_diff_empty_or_too_large} = Review.diff(snapshot, objects, fetch(responses))
  end

  test "propagates authorized fetch failures and rejects malformed contracts" do
    {snapshot, objects, _responses} = fixture(%{}, %{"file" => {"100644", "new"}})
    assert {:error, :forbidden} = Review.diff(snapshot, objects, fn _ -> {:error, :forbidden} end)
    assert {:error, :shipping_objects_invalid} = Review.diff(snapshot, objects, fn _ -> {:ok, %{}} end)
    assert {:error, :shipping_objects_invalid} = Review.diff(%{}, objects, fn _ -> flunk("must not fetch") end)
    assert {:error, :shipping_objects_invalid} = Review.diff(snapshot, nil, nil)
  end

  defp assert_invalid(snapshot, objects, responses) do
    assert {:error, :shipping_objects_invalid} = Review.diff(snapshot, objects, fetch(responses))
  end

  defp fetch(responses), do: fn path -> {:ok, Map.fetch!(responses, path)} end

  defp fixture(before, after_files) do
    base_tree = tree(before)
    new_tree = tree(after_files)
    identity = "Tuist Jams <jams@tuist.dev> 946684800 +0000"
    commit = "tree #{new_tree}\nparent #{@base}\nauthor #{identity}\ncommitter #{identity}\n\nTuist Jams #{@jam}\n"
    snapshot = %{base_sha: @base, head_sha: hash("commit", commit), jam_id: @jam}

    entries =
      before
      |> Map.keys()
      |> Kernel.++(Map.keys(after_files))
      |> Enum.uniq()
      |> Enum.reject(&(before[&1] == after_files[&1]))
      |> Enum.map(fn path ->
        {mode, data} = after_files[path] || before[path]
        entry = %{"path" => path, "mode" => mode, "type" => "blob", "sha" => nil}

        if Map.has_key?(after_files, path),
          do: Map.merge(entry, %{"sha" => hash("blob", data), "content" => Base.encode64(data)}),
          else: entry
      end)

    responses = %{
      "/git/commits/#{@base}" => %{"sha" => @base, "tree" => %{"sha" => base_tree}},
      "/git/trees/#{base_tree}?recursive=1" => %{"sha" => base_tree, "truncated" => false, "tree" => listing(before)}
    }

    responses =
      Enum.reduce(before, responses, fn {_path, {mode, data}}, responses ->
        if mode == "160000" do
          responses
        else
          sha = hash("blob", data)

          Map.put(responses, "/git/blobs/#{sha}", %{
            "sha" => sha,
            "encoding" => "base64",
            "size" => byte_size(data),
            "content" => Base.encode64(data)
          })
        end
      end)

    {snapshot, %{"tree_sha" => new_tree, "entries" => entries}, responses}
  end

  defp listing(files) do
    leaves =
      Enum.map(files, fn {path, {mode, data}} ->
        %{
          "path" => path,
          "mode" => mode,
          "type" => if(mode == "160000", do: "commit", else: "blob"),
          "sha" => if(mode == "160000", do: data, else: hash("blob", data))
        }
      end)

    directories =
      files
      |> Map.keys()
      |> Enum.flat_map(fn path ->
        parts = String.split(path, "/")
        if length(parts) > 1, do: Enum.map(1..(length(parts) - 1), &Enum.join(Enum.take(parts, &1), "/")), else: []
      end)
      |> Enum.uniq()
      |> Enum.map(fn path ->
        children =
          Map.new(
            for {name, data} <- files,
                String.starts_with?(name, path <> "/"),
                do: {String.replace_prefix(name, path <> "/", ""), data}
          )

        %{"path" => path, "mode" => "040000", "type" => "tree", "sha" => tree(children)}
      end)

    directories ++ leaves
  end

  defp tree(files) do
    files
    |> Enum.group_by(fn {path, _} -> hd(String.split(path, "/")) end)
    |> Enum.map(fn {name, items} ->
      case items do
        [{^name, {mode, data}}] ->
          {name, mode, if(mode == "160000", do: data, else: hash("blob", data))}

        _ ->
          children = Map.new(items, fn {path, value} -> {String.replace_prefix(path, name <> "/", ""), value} end)
          {name, "40000", tree(children)}
      end
    end)
    |> Enum.sort_by(fn {name, mode, _} -> name <> if(mode == "40000", do: "/", else: "") end)
    |> Enum.map(fn {name, mode, sha} -> [mode, " ", name, <<0>>, Base.decode16!(sha, case: :lower)] end)
    |> IO.iodata_to_binary()
    |> then(&hash("tree", &1))
  end

  defp hash(type, data), do: Base.encode16(:crypto.hash(:sha, "#{type} #{byte_size(data)}\0" <> data), case: :lower)

  defp temporary_directory do
    path = Path.join(System.tmp_dir!(), "tuist-review-test-" <> Base.url_encode64(:crypto.strong_rand_bytes(12)))
    File.mkdir!(path)
    path
  end
end
