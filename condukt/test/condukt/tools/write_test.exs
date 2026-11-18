defmodule Condukt.Tools.WriteTest do
  use ExUnit.Case, async: true

  alias Condukt.Sandbox
  alias Condukt.Tools.Write

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    {:ok, sandbox} = Sandbox.new(Sandbox.Local, cwd: tmp_dir)
    %{context: %{sandbox: sandbox, opts: []}}
  end

  test "creates new file", %{tmp_dir: tmp_dir, context: context} do
    {:ok, result} = Write.call(%{"path" => "new.txt", "content" => "Hello!"}, context)

    assert String.contains?(result, "Wrote new.txt")
    assert File.read!(Path.join(tmp_dir, "new.txt")) == "Hello!"
  end

  test "overwrites existing file", %{tmp_dir: tmp_dir, context: context} do
    path = Path.join(tmp_dir, "existing.txt")
    File.write!(path, "old content")

    {:ok, result} = Write.call(%{"path" => "existing.txt", "content" => "new content"}, context)

    assert String.contains?(result, "Wrote existing.txt")
    assert File.read!(path) == "new content"
  end

  test "creates parent directories", %{tmp_dir: tmp_dir, context: context} do
    {:ok, _result} = Write.call(%{"path" => "deep/nested/file.txt", "content" => "nested"}, context)

    assert File.read!(Path.join(tmp_dir, "deep/nested/file.txt")) == "nested"
  end
end
