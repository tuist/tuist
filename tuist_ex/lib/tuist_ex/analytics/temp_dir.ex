defmodule TuistEx.Analytics.TempDir do
  @moduledoc false

  # A fresh directory under the system's temporary one, with a random name
  # and only its owner allowed in. Jobs sharing a temporary directory cannot
  # read, overwrite or redirect each other's files, which a predictable file
  # name would allow.

  @doc """
  Calls `fun` with a new private directory and removes it afterwards.
  """
  def with_dir(prefix, fun) do
    name = Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
    dir = Path.join(System.tmp_dir!(), "#{prefix}-#{name}")
    File.mkdir!(dir)
    File.chmod!(dir, 0o700)

    try do
      fun.(dir)
    after
      File.rm_rf(dir)
    end
  end
end
