defmodule Tuist.Jams.Review do
  @moduledoc """
  Builds a review from authenticated upstream base objects and untrusted exported
  blobs, never from guest Git output. `diff/3` returns `{:ok, binary_patch}` or
  `{:error, category}`. The fetch callback receives GitHub REST-relative paths
  and must perform authorized, bounded contents-read requests in the server.

  Only SHA-1 repositories are supported. Exported entries may add, replace or
  delete regular/executable files and symlinks; submodules are preserved, never
  changed. A deletion has a nil SHA and absent/nil content. All other entries
  carry a SHA and Base64 bytes. Guest diff fields are ignored. The entire tree
  and canonical single-parent commit must match the advertised tree and head.
  """

  @new_limit 524_288
  @old_limit 1_048_576
  @diff_limit 131_072
  @blob_modes ["100644", "100755", "120000"]
  @invalid :shipping_objects_invalid

  def diff(snapshot, objects, fetch) when is_map(snapshot) and is_map(objects) and is_function(fetch, 1) do
    validate_snapshot!(snapshot)
    entries = exported_entries!(objects)
    base_tree = base_tree!(snapshot.base_sha, fetch)

    with_store(fn store ->
      {base, base_sha} = trusted_tree!(base_tree, store, fetch)
      changed = apply_entries!(base, entries)
      tree_sha = write_tree!(changed, store)
      require!(tree_sha == objects["tree_sha"])
      require!(object_sha("commit", commit(snapshot, tree_sha)) == snapshot.head_sha)
      fetch_old_blobs!(base, entries, store, fetch)
      Enum.each(entries, fn entry -> if entry.data, do: write_object!(store, "blob", entry.data) end)
      render_diff(store, base_sha, tree_sha)
    end)
  rescue
    _error in [File.Error, ErlangError, ArgumentError] -> {:error, :shipping_review_unavailable}
  catch
    {:review_error, category} -> {:error, category}
  end

  def diff(_, _, _), do: {:error, @invalid}

  defp validate_snapshot!(snapshot) do
    require!(sha?(Map.get(snapshot, :base_sha)) and sha?(Map.get(snapshot, :head_sha)))
    id = Map.get(snapshot, :jam_id)
    require!(is_binary(id) and byte_size(id) in 1..128 and Regex.match?(~r/\A[a-zA-Z0-9-]+\z/, id))
  end

  defp exported_entries!(objects) do
    require!(sha?(objects["tree_sha"]))
    entries = objects["entries"]
    require!(is_list(entries) and length(entries) <= 200)

    {entries, _paths, _total} =
      Enum.reduce(entries, {[], MapSet.new(), 0}, fn entry, {result, paths, total} ->
        require!(is_map(entry))
        path = entry["path"]
        require!(safe_path?(path) and not MapSet.member?(paths, path))
        require!(entry["type"] == "blob" and entry["mode"] in @blob_modes)

        data =
          case {entry["sha"], entry["content"]} do
            {nil, nil} ->
              nil

            {sha, encoded} ->
              require!(sha?(sha))
              data = decode!(encoded, @new_limit)
              require!(object_sha("blob", data) == sha)
              data
          end

        total = total + if(data, do: byte_size(data), else: 0)
        require!(total <= @new_limit)
        value = %{path: path, mode: entry["mode"], sha: entry["sha"], data: data}
        {[value | result], MapSet.put(paths, path), total}
      end)

    entries
  end

  defp base_tree!(base_sha, fetch) do
    case fetch!(fetch, "/git/commits/#{base_sha}") do
      %{"sha" => ^base_sha, "tree" => %{"sha" => tree_sha}} ->
        require!(sha?(tree_sha))
        tree_sha

      _ ->
        fail!()
    end
  end

  defp trusted_tree!(root_sha, store, fetch) do
    response = fetch!(fetch, "/git/trees/#{root_sha}?recursive=1")
    require!(is_map(response) and response["sha"] == root_sha and response["truncated"] == false)
    entries = response["tree"]
    require!(is_list(entries) and length(entries) <= 50_000)

    {flat, expected} = Enum.reduce(entries, {%{}, %{"" => root_sha}}, &put_tree_entry!/2)

    # Explicit parent directories and every subtree hash are checked, not just
    # a leaf inventory which could omit a submodule or an empty tree.
    Enum.each(flat, fn {path, _} ->
      parent = parent(path)
      require!(parent == "" or match?({"040000", _}, flat[parent]))
    end)

    grouped = Enum.group_by(flat, fn {path, _} -> parent(path) end)
    tree = build_base!("", grouped, expected, store)
    {tree, root_sha}
  end

  defp put_tree_entry!(entry, {flat, expected}) do
    require!(is_map(entry))
    path = entry["path"]
    require!(safe_path?(path) and not Map.has_key?(flat, path) and sha?(entry["sha"]))
    mode = entry["mode"]
    type = entry["type"]

    require!(
      (mode in @blob_modes and type == "blob") or (mode == "040000" and type == "tree") or
        (mode == "160000" and type == "commit")
    )

    expected = if type == "tree", do: Map.put(expected, path, entry["sha"]), else: expected
    {Map.put(flat, path, {mode, entry["sha"]}), expected}
  end

  defp build_base!(path, grouped, expected, store) do
    {tree, shallow} =
      Enum.reduce(Map.get(grouped, path, []), {%{}, %{}}, fn {child, {mode, sha}}, {tree, shallow} ->
        name = List.last(String.split(child, "/"))
        value = if mode == "040000", do: build_base!(child, grouped, expected, store), else: {mode, sha}
        # Children were already verified. Hash this level only, avoiding a
        # repeated traversal/write of each descendant for every ancestor.
        mode = if mode == "040000", do: "40000", else: mode
        {Map.put(tree, name, value), Map.put(shallow, name, {mode, sha})}
      end)

    require!(write_tree!(shallow, store) == expected[path])
    tree
  end

  defp apply_entries!(tree, entries) do
    # Delete first so a file can become a directory and vice versa. An export
    # cannot remove/move a submodule, even by replacing a containing directory.
    tree =
      entries
      |> Enum.filter(&is_nil(&1.data))
      |> Enum.reduce(tree, fn entry, tree ->
        require!(match?({mode, _} when mode in @blob_modes, lookup(tree, entry.path)))
        change!(tree, String.split(entry.path, "/"), nil)
      end)

    entries
    |> Enum.reject(&is_nil(&1.data))
    |> Enum.reduce(tree, fn entry, tree ->
      old = lookup(tree, entry.path)
      require!(is_nil(old) or match?({mode, _} when mode in @blob_modes, old))
      change!(tree, String.split(entry.path, "/"), {entry.mode, entry.sha})
    end)
  end

  defp lookup(tree, path) do
    Enum.reduce_while(String.split(path, "/"), tree, fn part, node ->
      if is_map(node), do: {:cont, Map.get(node, part)}, else: {:halt, nil}
    end)
  end

  defp change!(tree, [name], nil), do: Map.delete(tree, name)
  defp change!(tree, [name], value), do: Map.put(tree, name, value)

  defp change!(tree, [name | rest], value) do
    child = Map.get(tree, name, %{})
    require!(is_map(child))
    child = change!(child, rest, value)
    if map_size(child) == 0, do: Map.delete(tree, name), else: Map.put(tree, name, child)
  end

  defp fetch_old_blobs!(tree, entries, store, fetch) do
    entries
    |> Enum.map(&lookup(tree, &1.path))
    |> Enum.filter(&match?({mode, _} when mode in @blob_modes, &1))
    |> Enum.map(&elem(&1, 1))
    |> Enum.uniq()
    |> Enum.reduce(0, fn sha, total ->
      response = fetch!(fetch, "/git/blobs/#{sha}")
      require!(is_map(response) and response["sha"] == sha and response["encoding"] == "base64")
      size = response["size"]
      require!(is_integer(size) and size >= 0 and size <= @old_limit and total + size <= @old_limit)
      data = decode!(response["content"], @old_limit)
      require!(byte_size(data) == size and object_sha("blob", data) == sha)
      write_object!(store, "blob", data)
      total + size
    end)
  end

  defp write_tree!(tree, store) do
    data =
      tree
      |> Enum.sort_by(fn {name, value} ->
        if is_map(value) or match?({"40000", _}, value), do: name <> "/", else: name
      end)
      |> Enum.map(fn {name, value} ->
        {mode, sha} = if is_map(value), do: {"40000", write_tree!(value, store)}, else: value
        [mode, " ", name, <<0>>, Base.decode16!(sha, case: :lower)]
      end)
      |> IO.iodata_to_binary()

    write_object!(store, "tree", data)
  end

  defp commit(snapshot, tree_sha) do
    identity = "Tuist Jams <jams@tuist.dev> 946684800 +0000"

    "tree #{tree_sha}\nparent #{snapshot.base_sha}\nauthor #{identity}\ncommitter #{identity}\n\nTuist Jams #{snapshot.jam_id}\n"
  end

  defp object_data(type, data), do: type <> " " <> Integer.to_string(byte_size(data)) <> <<0>> <> data
  defp object_sha(type, data), do: Base.encode16(:crypto.hash(:sha, object_data(type, data)), case: :lower)

  defp write_object!(store, type, data) do
    sha = object_sha(type, data)
    path = Path.join([store, "objects", binary_part(sha, 0, 2), binary_part(sha, 2, 38)])

    if !File.exists?(path) do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, :zlib.compress(object_data(type, data)))
    end

    sha
  end

  defp with_store(fun) do
    {:ok, path} = Briefly.create(directory: true)

    try do
      File.chmod!(path, 0o700)
      File.mkdir_p!(Path.join(path, "objects"))
      File.mkdir_p!(Path.join(path, "refs"))
      File.write!(Path.join(path, "HEAD"), "ref: refs/heads/review\n")
      File.write!(Path.join(path, "config"), "[core]\n\tbare = true\n\trepositoryformatversion = 0\n")
      fun.(path)
    after
      File.rm_rf(path)
    end
  end

  defp render_diff(store, base, head) do
    output = Path.join(store, "review.patch")
    git = System.find_executable("git")
    if is_nil(git), do: throw({:review_error, :shipping_review_unavailable})
    # Clear all inherited Git configuration/object-store overrides. There is no
    # checkout, attributes file, remote, credential, external diff or textconv.
    env =
      System.get_env()
      |> Enum.filter(fn {key, _} -> String.starts_with?(key, "GIT_") end)
      |> Map.new(fn {key, _} -> {key, nil} end)
      |> Map.merge(%{
        "GIT_CONFIG_NOSYSTEM" => "1",
        "GIT_CONFIG_GLOBAL" => "/dev/null",
        "GIT_ATTR_NOSYSTEM" => "1",
        "GIT_TERMINAL_PROMPT" => "0",
        "GIT_ALLOW_PROTOCOL" => "",
        "GIT_NO_LAZY_FETCH" => "1",
        "HOME" => store,
        "XDG_CONFIG_HOME" => store,
        "LC_ALL" => "C"
      })

    args = [
      "--git-dir=#{store}",
      "-c",
      "core.hooksPath=/dev/null",
      "-c",
      "core.attributesFile=/dev/null",
      "diff",
      "--no-ext-diff",
      "--no-textconv",
      "--binary",
      "--no-renames",
      "--no-color",
      "--no-relative",
      "--src-prefix=a/",
      "--dst-prefix=b/",
      "--ignore-submodules=all",
      "--output=#{output}",
      base,
      head,
      "--"
    ]

    # Discard stdout/stderr rather than accumulating diagnostics; the patch is
    # written to disposable disk and read only after checking its size.
    case MuonTrap.cmd(git, args,
           cd: store,
           env: env,
           timeout: 15_000,
           into: File.stream!("/dev/null"),
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        size = File.stat!(output).size

        if size in 1..@diff_limit,
          do: {:ok, File.read!(output)},
          else: {:error, :shipping_diff_empty_or_too_large}

      _ ->
        {:error, :shipping_review_unavailable}
    end
  end

  defp fetch!(fetch, path) do
    case fetch.(path) do
      {:ok, body} -> body
      {:error, category} -> throw({:review_error, category})
      _ -> fail!()
    end
  end

  defp decode!(encoded, limit) do
    # GitHub wraps Base64 at 60 columns. Bound before removing whitespace or
    # decoding, so even malformed encoded content cannot allocate unboundedly.
    require!(is_binary(encoded) and byte_size(encoded) <= div(limit + 2, 3) * 4 + div(limit, 30) + 16)

    case Base.decode64(encoded, ignore: :whitespace) do
      {:ok, data} when byte_size(data) <= limit -> data
      _ -> fail!()
    end
  end

  defp safe_path?(path) when is_binary(path) and byte_size(path) in 1..4096 do
    parts = String.split(path, "/")

    String.valid?(path) and length(parts) <= 64 and not String.contains?(path, [<<0>>, "\\"]) and
      Enum.all?(parts, fn part ->
        byte_size(part) in 1..255 and part not in [".", ".."] and String.downcase(part) != ".git"
      end)
  end

  defp safe_path?(_), do: false
  defp parent(path), do: path |> String.split("/") |> Enum.drop(-1) |> Enum.join("/")
  defp sha?(sha), do: is_binary(sha) and byte_size(sha) == 40 and Regex.match?(~r/\A[0-9a-f]{40}\z/, sha)
  defp require!(true), do: :ok
  defp require!(_), do: fail!()
  defp fail!, do: throw({:review_error, @invalid})
end
