defmodule Tuist.Docs.Tools.SafePath do
  @moduledoc false

  @doc """
  Resolves `relative` against `root` and ensures the result stays inside
  `root` (no `..` traversal, no absolute escape, no symlink jumps).

  Returns `{:ok, absolute_path}` or `{:error, :unsafe_path}`.
  """
  def resolve(root, relative) when is_binary(root) and is_binary(relative) do
    relative = String.trim_leading(relative, "/")

    with {:ok, safe} <- safe_relative(relative),
         absolute = Path.expand(safe, root),
         true <- inside?(absolute, root) do
      {:ok, absolute}
    else
      _ -> {:error, :unsafe_path}
    end
  end

  defp safe_relative(path) do
    case Path.safe_relative(path) do
      {:ok, safe} -> {:ok, safe}
      :error -> :error
    end
  end

  defp inside?(absolute, root) do
    expanded_root = Path.expand(root)
    String.starts_with?(absolute <> "/", expanded_root <> "/") or absolute == expanded_root
  end
end
