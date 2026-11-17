defmodule Tuist.Threads.CheckoutTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Sandboxes.Uploads
  alias Tuist.Threads.Checkout
  alias Tuist.Threads.Repository

  setup do
    user = user_fixture()
    sandbox = Repo.insert!(%Sandbox{account_id: user.account.id, state: :running})
    origin = Briefly.create!(directory: true)

    git!(origin, ["init", "--quiet", "--initial-branch=main"])
    File.write!(Path.join(origin, "README.md"), "first\n")
    git!(origin, ["add", "."])
    git!(origin, ["commit", "--quiet", "-m", "First"])
    File.write!(Path.join(origin, "README.md"), "second\n")
    git!(origin, ["commit", "--quiet", "-am", "Second"])
    base = String.trim(git!(origin, ["rev-parse", "HEAD"]))

    # Repository.environment/3 supplies the credential header in production;
    # here it points GitHub's URL at the local repository instead.
    stub(Repository, :environment, fn _, "Tuist/Example", :read ->
      {:ok,
       %{
         "GIT_ALLOW_PROTOCOL" => "https:file",
         "GIT_CONFIG_COUNT" => "2",
         "GIT_CONFIG_KEY_0" => "url.file://#{origin}/.insteadOf",
         "GIT_CONFIG_VALUE_0" => "https://github.com/Tuist/Example.git",
         "GIT_CONFIG_KEY_1" => "protocol.file.allow",
         "GIT_CONFIG_VALUE_1" => "always"
       }}
    end)

    %{account: user.account, sandbox: sandbox, base: base, origin: origin}
  end

  test "stages one commit of the base that unpacks into a checkout with no credentials", c do
    unpacked = Briefly.create!(directory: true)

    expect(Uploads, :stage_file, fn account, sandbox, archive ->
      assert account.id == c.account.id
      assert sandbox.id == c.sandbox.id
      # Unpack the archive as the guest's script does.
      File.mkdir_p!(Path.join(unpacked, ".git"))
      {_, 0} = System.cmd("tar", ["-xf", archive, "-C", Path.join(unpacked, ".git")])
      {:ok, "https://storage.example.com/checkout"}
    end)

    assert {:ok, "https://storage.example.com/checkout"} = Checkout.stage(c.account, c.sandbox, "Tuist/Example", c.base)

    git!(unpacked, ["config", "core.bare", "false"])
    git!(unpacked, ["checkout", "--quiet", "-b", "threads/1", c.base])
    assert String.trim(git!(unpacked, ["rev-parse", "HEAD"])) == c.base
    assert File.read!(Path.join(unpacked, "README.md")) == "second\n"
    assert String.trim(git!(unpacked, ["rev-list", "--count", "HEAD"])) == "1"
    assert String.trim(git!(unpacked, ["remote", "get-url", "origin"])) == "https://github.com/Tuist/Example.git"
    refute File.read!(Path.join([unpacked, ".git", "config"])) =~ ~r/extraheader|insteadOf/i
  end

  test "only HTTPS reaches a remote, whatever the URL is rewritten to", c do
    # The same redirect to the local repository, without the test's protocol
    # overrides: the server's own allow list must refuse file://.
    stub(Repository, :environment, fn _, "Tuist/Example", :read ->
      {:ok,
       %{
         "GIT_CONFIG_COUNT" => "1",
         "GIT_CONFIG_KEY_0" => "url.file://#{c.origin}/.insteadOf",
         "GIT_CONFIG_VALUE_0" => "https://github.com/Tuist/Example.git"
       }}
    end)

    reject(Uploads, :stage_file, 3)
    assert {:error, :checkout_unavailable} = Checkout.stage(c.account, c.sandbox, "Tuist/Example", c.base)
  end

  test "a repository GitHub reports as too large is refused before anything is fetched" do
    assert :ok = Checkout.fits(%{name: "Tuist/Example", size: 1024})
    assert :ok = Checkout.fits(%{name: "Tuist/Example", size: nil})
    assert {:error, :repository_too_large} = Checkout.fits(%{name: "Tuist/Example", size: 5 * 1024 * 1024})
  end

  test "a commit the repository does not have stages nothing", c do
    reject(Uploads, :stage_file, 3)
    missing = String.duplicate("b", 40)
    assert {:error, :checkout_unavailable} = Checkout.stage(c.account, c.sandbox, "Tuist/Example", missing)
  end

  defp git!(cd, args) do
    env = [
      {"GIT_CONFIG_NOSYSTEM", "1"},
      {"GIT_CONFIG_GLOBAL", "/dev/null"},
      {"GIT_AUTHOR_NAME", "Test"},
      {"GIT_AUTHOR_EMAIL", "test@tuist.dev"},
      {"GIT_COMMITTER_NAME", "Test"},
      {"GIT_COMMITTER_EMAIL", "test@tuist.dev"}
    ]

    {output, 0} = System.cmd("git", args, cd: cd, env: env, stderr_to_stdout: true)
    output
  end
end
