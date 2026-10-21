defmodule TuistEx.Cache.Key do
  @moduledoc false

  @version 1

  def build(inputs), do: digest({@version, inputs})

  def digest(value) do
    :crypto.hash(:sha256, :erlang.term_to_binary(value, [:deterministic]))
    |> Base.encode16(case: :lower)
  end

  # Enumerating names as well as bytes catches new, removed and missing inputs.
  # Never follow links: a dependency can otherwise read outside the modeled tree.
  def tree(path), do: walk(Path.expand(path), "", true)

  def paths(path), do: path |> Path.expand() |> walk("", false) |> Enum.map(&elem(&1, 0))

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

  defp walk(root, relative, contents?) do
    path = if relative == "", do: root, else: Path.join(root, relative)

    case File.lstat(path) do
      {:ok, %{type: :regular, mode: mode}} ->
        if contents?,
          do: [{relative, Bitwise.band(mode, 0o111), digest(File.read!(path))}],
          else: [{relative, :regular}]

      {:ok, %{type: :directory}} ->
        [{relative, :directory}] ++
          (path
           |> File.ls!()
           |> Enum.reject(&(relative == "" and &1 in [".git", "_build"]))
           |> Enum.sort()
           |> Enum.flat_map(&walk(root, Path.join(relative, &1), contents?)))

      {:error, :enoent} ->
        [{relative, :missing}]

      _ ->
        throw(:unmodeled_input)
    end
  end
end
