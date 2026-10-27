defmodule Tuist.VCS.RemoteURLTest do
  use ExUnit.Case, async: true

  alias Tuist.VCS.RemoteURL

  describe "strip_credentials/1" do
    test "removes a user and token from an https remote" do
      assert RemoteURL.strip_credentials("https://x-access-token:fake-token@github.com/tuist/tuist.git") ==
               "https://github.com/tuist/tuist.git"
    end

    test "removes a token passed as the username" do
      assert RemoteURL.strip_credentials("https://fake-token@github.com/tuist/tuist.git") ==
               "https://github.com/tuist/tuist.git"
    end

    test "keeps a non-default port" do
      assert RemoteURL.strip_credentials("https://oauth2:fake-token@gitlab.example.com:8443/tuist/tuist.git") ==
               "https://gitlab.example.com:8443/tuist/tuist.git"
    end

    test "returns an https remote without userinfo unchanged" do
      assert RemoteURL.strip_credentials("https://github.com/tuist/tuist.git") == "https://github.com/tuist/tuist.git"
    end

    test "returns an scp-style remote unchanged" do
      assert RemoteURL.strip_credentials("git@github.com:tuist/tuist.git") == "git@github.com:tuist/tuist.git"
    end

    test "returns nil unchanged" do
      assert RemoteURL.strip_credentials(nil) == nil
    end
  end

  describe "strip_credentials_from_params/1" do
    test "strips atom and string keyed remotes" do
      assert RemoteURL.strip_credentials_from_params(%{
               git_remote_url_origin: "https://x-access-token:fake-token@github.com/tuist/tuist.git",
               git_ref: "refs/pull/1/merge"
             }) == %{git_remote_url_origin: "https://github.com/tuist/tuist.git", git_ref: "refs/pull/1/merge"}

      assert RemoteURL.strip_credentials_from_params(%{
               "git_remote_url_origin" => "https://x-access-token:fake-token@github.com/tuist/tuist.git"
             }) == %{"git_remote_url_origin" => "https://github.com/tuist/tuist.git"}
    end

    test "leaves maps without a remote untouched" do
      assert RemoteURL.strip_credentials_from_params(%{git_ref: "refs/heads/main"}) == %{git_ref: "refs/heads/main"}
    end
  end
end
