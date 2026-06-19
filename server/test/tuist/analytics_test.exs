defmodule Tuist.AnalyticsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import TelemetryTest

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Analytics
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup [:telemetry_listen]

  describe "organization_create" do
    @describetag telemetry_listen: [:analytics, :organization, :create]

    test "it sends the telemetry event" do
      # When
      user = AccountsFixtures.user_fixture()

      assert :ok =
               Analytics.organization_create("test", user)

      # Then
      expected_metadata = %{email: user.email, name: "test", user_id: user.id}

      assert_receive {:telemetry_event,
                      %{
                        event: [:analytics, :organization, :create],
                        measurements: %{},
                        metadata: ^expected_metadata
                      }}
    end
  end

  describe "user_authenticate" do
    @describetag telemetry_listen: [:analytics, :user, :authenticate]

    test "it sends the telemetry event" do
      # When
      user = AccountsFixtures.user_fixture()

      assert :ok = Analytics.user_authenticate(user)

      # Then
      expected_metadata = %{email: user.email, user_id: user.id}

      assert_receive {:telemetry_event,
                      %{
                        event: [:analytics, :user, :authenticate],
                        measurements: %{},
                        metadata: ^expected_metadata
                      }}
    end
  end

  describe "page_view" do
    @describetag telemetry_listen: [:analytics, :page, :view]

    test "it sends the telemetry event" do
      # When
      user = AccountsFixtures.user_fixture()

      assert :ok = Analytics.page_view("/foo", user)

      # Then
      expected_metadata = %{user_id: user.id, path: "/foo"}

      assert_receive {:telemetry_event,
                      %{
                        event: [:analytics, :page, :view],
                        measurements: %{},
                        metadata: ^expected_metadata
                      }}
    end
  end

  describe "preview_upload" do
    @describetag telemetry_listen: [:analytics, :preview, :upload]

    test "it sends the telemetry event" do
      # When
      user = AccountsFixtures.user_fixture()

      assert :ok = Analytics.preview_upload(user)

      # Then
      expected_metadata = %{user_id: user.id}

      assert_receive {:telemetry_event,
                      %{
                        event: [:analytics, :preview, :upload],
                        measurements: %{},
                        metadata: ^expected_metadata
                      }}
    end

    test "it sends the telemetry event with an authenticated account" do
      # When
      user = AccountsFixtures.user_fixture()
      authenticated_account = %AuthenticatedAccount{account: user.account, scopes: []}

      assert :ok = Analytics.preview_upload(authenticated_account)

      # Then
      expected_metadata = %{account_id: user.account.id}

      assert_receive {:telemetry_event,
                      %{
                        event: [:analytics, :preview, :upload],
                        measurements: %{},
                        metadata: ^expected_metadata
                      }}
    end
  end

  describe "preview_download" do
    @describetag telemetry_listen: [:analytics, :preview, :download]

    test "it sends the telemetry event" do
      # When
      user = AccountsFixtures.user_fixture()

      assert :ok = Analytics.preview_download(user)

      # Then
      expected_metadata = %{user_id: user.id}

      assert_receive {:telemetry_event,
                      %{
                        event: [:analytics, :preview, :download],
                        measurements: %{},
                        metadata: ^expected_metadata
                      }}
    end
  end
end
