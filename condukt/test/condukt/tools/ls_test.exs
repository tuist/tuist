defmodule Condukt.Tools.LsTest do
  use ExUnit.Case, async: true

  alias Condukt.Sandbox
  alias Condukt.Tools.Ls

  @moduletag :tmp_dir

  # Lists through `exec/3`, as a sandbox without `list_dir/2` does.
  defmodule ShellOnly do
    @behaviour Condukt.Sandbox

    @impl true
    def init(opts), do: Sandbox.Local.init(opts)
    @impl true
    def shutdown(_state), do: :ok
    @impl true
    def read_file(state, path), do: Sandbox.Local.read_file(state, path)
    @impl true
    def write_file(state, path, content), do: Sandbox.Local.write_file(state, path, content)
    @impl true
    def edit_file(state, path, old, new), do: Sandbox.Local.edit_file(state, path, old, new)
    @impl true
    def exec(state, command, opts), do: Sandbox.Local.exec(state, command, opts)
    @impl true
    def cwd(state), do: Sandbox.Local.cwd(state)
  end

  setup %{tmp_dir: tmp_dir} do
    File.mkdir_p!(Path.join(tmp_dir, "Beta"))
    File.write!(Path.join(tmp_dir, "alpha.txt"), "")
    File.write!(Path.join(tmp_dir, ".hidden"), "")
    File.write!(Path.join(tmp_dir, "it's here"), "")
    :ok
  end

  for module <- [Sandbox.Local, ShellOnly] do
    test "lists sorted entries with dotfiles and directory slashes on #{inspect(module)}", %{tmp_dir: tmp_dir} do
      {:ok, sandbox} = Sandbox.new(unquote(module), cwd: tmp_dir)
      context = %{sandbox: sandbox, opts: []}

      assert {:ok, ".hidden\nalpha.txt\nBeta/\nit's here"} = Ls.call(%{}, context)

      assert {:ok, ".hidden\nalpha.txt\n\n[2 entries limit reached. Use limit=4 for more]"} =
               Ls.call(%{"limit" => 2}, context)

      assert {:ok, "(empty directory)"} = Ls.call(%{"path" => "Beta"}, context)
      assert {:error, "Path not found: nope"} = Ls.call(%{"path" => "nope"}, context)
      assert {:error, "Not a directory: alpha.txt"} = Ls.call(%{"path" => "alpha.txt"}, context)
    end
  end
end
