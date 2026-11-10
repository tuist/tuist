defmodule TuistEx.Cache.Key do
  @moduledoc false

  @version 2

  def build(inputs), do: digest({@version, inputs})

  def digest(value) do
    :crypto.hash(:sha256, :erlang.term_to_binary(value, [:deterministic]))
    |> Base.encode16(case: :lower)
  end

  # Enumerating names as well as bytes catches new, removed and missing inputs.
  # Source links are rejected. Output resources may retain relative links only
  # when their resolved targets stay inside the independently hashed tree.
  def tree(path, generated \\ [], contained_links? \\ false) do
    root = if contained_links?, do: canonical_path(path), else: Path.expand(path)
    walk(root, "", true, generated, contained_links?)
  end

  def paths(path, generated \\ []),
    do: path |> Path.expand() |> walk("", false, generated, false) |> Enum.map(&elem(&1, 0))

  # Keep the checkout root when scanning a source subdirectory: nested .git and
  # _build names are inputs, not the checkout's ignored metadata directories.
  def paths_in(path, directory) do
    root = Path.expand(path)
    relative = Path.relative_to(Path.expand(directory, root), root)
    relative = if relative == ".", do: "", else: relative

    if Path.type(relative) != :relative or List.first(Path.split(relative)) in [".git", "_build"],
      do: throw(:unmodeled_input)

    relative
    |> Path.split()
    |> Enum.drop(-1)
    |> Enum.reduce(root, fn name, parent ->
      reject_source_link!(parent)
      Path.join(parent, name)
    end)
    |> reject_source_link!()

    root |> walk(relative, false, [], false) |> Enum.map(&elem(&1, 0))
  end

  defp reject_source_link!(path) do
    case File.lstat(path) do
      {:ok, %{type: :symlink}} -> throw(:unmodeled_input)
      {:ok, _} -> :ok
      {:error, :enoent} -> :ok
      _ -> throw(:unmodeled_input)
    end
  end

  # Resolve directory aliases only for store containment checks, not input discovery.
  def canonical_path(path), do: resolve(Path.expand(path), 40)

  defp resolve(_, 0), do: throw(:unmodeled_input)

  defp resolve(path, remaining) do
    parent = Path.dirname(path)

    if parent == path do
      path
    else
      path = Path.join(resolve(parent, remaining), Path.basename(path))

      case File.read_link(path) do
        {:ok, target} -> resolve(Path.expand(target, Path.dirname(path)), remaining - 1)
        {:error, reason} when reason in [:einval, :enoent] -> path
        _ -> throw(:unmodeled_input)
      end
    end
  end

  defp walk(root, relative, contents?, generated, contained_links?) do
    if Enum.any?(generated, &(relative == &1 or String.starts_with?(relative, &1 <> "/"))) do
      []
    else
      walk_entry(root, relative, contents?, generated, contained_links?)
    end
  end

  defp walk_entry(root, relative, contents?, generated, contained_links?) do
    path = if relative == "", do: root, else: Path.join(root, relative)

    case File.lstat(path) do
      {:ok, %{type: :regular, mode: mode}} ->
        if contents?,
          do: [{relative, Bitwise.band(mode, 0o111), digest(File.read!(path))}],
          else: [{relative, :regular}]

      {:ok, %{type: :directory}} ->
        marker =
          if relative != "" and Enum.any?(generated, &String.starts_with?(&1, relative <> "/")),
            do: [],
            else: [{relative, :directory}]

        marker ++
          (path
           |> File.ls!()
           |> Enum.reject(&(not contained_links? and relative == "" and &1 in [".git", "_build"]))
           |> Enum.sort()
           |> Enum.flat_map(
             &walk(root, Path.join(relative, &1), contents?, generated, contained_links?)
           ))

      {:ok, %{type: :symlink}} when contained_links? and relative != "" ->
        target = File.read_link!(path)
        resolved = canonical_path(path)
        target_path = Path.relative_to(resolved, root)

        if Path.type(target) != :relative or target_path == resolved or
             not File.exists?(resolved),
           do: throw(:unmodeled_input)

        [{relative, :symlink, target}]

      {:error, :enoent} ->
        [{relative, :missing}]

      _ ->
        throw(:unmodeled_input)
    end
  end
end
