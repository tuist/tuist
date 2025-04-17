defmodule Tuist.Registry.Swift.Packages.PackageDownloadEventTest do
  use TuistTestSupport.Cases.DataCase

  alias Tuist.Registry.Swift.Packages.PackageDownloadEvent
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.Registry.Swift.PackagesFixtures

  describe "create_changeset/1" do
    test "ensures account_id is present" do
      # Given
      package_download_event = %PackageDownloadEvent{}

      # When
      got = PackageDownloadEvent.create_changeset(package_download_event, %{})

      # Then
      assert "can't be blank" in errors_on(got).account_id
    end

    test "ensures package_release_id is present" do
      # Given
      package_download_event = %PackageDownloadEvent{}

      # When
      got = PackageDownloadEvent.create_changeset(package_download_event, %{})

      # Then
      assert "can't be blank" in errors_on(got).package_release_id
    end

    test "is valid when contains all necessary attributes" do
      # Given
      package_release = PackagesFixtures.package_release_fixture()
      account = AccountsFixtures.user_fixture(preload: [:account]).account

      # When
      got =
        PackageDownloadEvent.create_changeset(%PackageDownloadEvent{}, %{
          package_release_id: package_release.id,
          account_id: account.id
        })

      # Then
      assert got.valid?
    end
  end
end
