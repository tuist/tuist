defmodule TuistWeb.TimezoneTest do
  use TuistTestSupport.Cases.LiveCase, async: true

  alias Phoenix.LiveView
  alias TuistWeb.Timezone

  describe "on_mount :assign_timezone" do
    test "assigns timezone from session when available" do
      # Given
      session = %{"user_timezone" => "America/New_York"}
      socket = %LiveView.Socket{}

      # When
      {:cont, updated_socket} = Timezone.on_mount(:assign_timezone, %{}, session, socket)

      # Then
      assert updated_socket.assigns.user_timezone == "America/New_York"
    end

    test "assigns timezone from connect params when session has no timezone" do
      # Given
      session = %{}
      socket = %LiveView.Socket{}

      # Stub the connect params to return timezone
      stub(LiveView, :get_connect_params, fn _socket ->
        %{"user_timezone" => "Europe/London"}
      end)

      # When
      {:cont, updated_socket} = Timezone.on_mount(:assign_timezone, %{}, session, socket)

      # Then
      assert updated_socket.assigns.user_timezone == "Europe/London"
    end

    test "assigns nil when no timezone in session or connect params" do
      # Given
      session = %{}
      socket = %LiveView.Socket{}

      # Stub the connect params to return nil
      stub(LiveView, :get_connect_params, fn _socket -> %{} end)

      # When
      {:cont, updated_socket} = Timezone.on_mount(:assign_timezone, %{}, session, socket)

      # Then
      assert updated_socket.assigns.user_timezone == nil
    end

    test "assigns nil when get_connect_params returns nil" do
      # Given
      session = %{}
      socket = %LiveView.Socket{}

      # Stub the connect params to return nil
      stub(LiveView, :get_connect_params, fn _socket -> nil end)

      # When
      {:cont, updated_socket} = Timezone.on_mount(:assign_timezone, %{}, session, socket)

      # Then
      assert updated_socket.assigns.user_timezone == nil
    end
  end
end
