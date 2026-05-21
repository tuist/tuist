defmodule Tuist.XcodeMirrorTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.XcodeMirror
  alias Tuist.XcodeMirror.AppleReleases
  alias Tuist.XcodeMirror.Registry

  setup :verify_on_exit!

  describe "missing_versions/1" do
    test "returns versions Apple has released but our mirror doesn't have, newest-first" do
      expect(AppleReleases, :list_released, fn _opts ->
        {:ok, ["26.5", "26.4.1", "26.3", "26.2.1", "26.1", "26.0.1"]}
      end)

      expect(Registry, :list_mirrored_tags, fn _opts ->
        {:ok, ["26.4.1", "26.3", "26.0.1"]}
      end)

      assert {:ok, ["26.5", "26.2.1", "26.1"]} = XcodeMirror.missing_versions()
    end

    test "empty list when the mirror is fully caught up" do
      expect(AppleReleases, :list_released, fn _ ->
        {:ok, ["26.5", "26.4.1"]}
      end)

      expect(Registry, :list_mirrored_tags, fn _ ->
        {:ok, ["26.5", "26.4.1"]}
      end)

      assert {:ok, []} = XcodeMirror.missing_versions()
    end

    test "Apple-list failure propagates with no Registry call" do
      expect(AppleReleases, :list_released, fn _ ->
        {:error, {:bad_status, 503}}
      end)

      # No expect for Registry — Mimic would fail verify_on_exit! if
      # `missing_versions/1` reached into the registry after the
      # first error.

      assert {:error, {:bad_status, 503}} = XcodeMirror.missing_versions()
    end

    test "Registry failure propagates" do
      expect(AppleReleases, :list_released, fn _ ->
        {:ok, ["26.5", "26.4.1"]}
      end)

      expect(Registry, :list_mirrored_tags, fn _ ->
        {:error, :auth_required}
      end)

      assert {:error, :auth_required} = XcodeMirror.missing_versions()
    end

    test "newest-first ordering puts patch-form versions ahead of bare major-minor" do
      expect(AppleReleases, :list_released, fn _ ->
        {:ok, ["26.4", "26.4.2", "26.4.1"]}
      end)

      expect(Registry, :list_mirrored_tags, fn _ -> {:ok, []} end)

      # 26.4.2 > 26.4.1 > 26.4 (the bare form sorts lowest because
      # `parse_version` zero-fills missing segments).
      assert {:ok, ["26.4.2", "26.4.1", "26.4"]} = XcodeMirror.missing_versions()
    end
  end
end
