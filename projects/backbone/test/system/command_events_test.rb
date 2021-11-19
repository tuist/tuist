# frozen_string_literal: true

require "application_system_test_case"

class CommandEventsTest < ApplicationSystemTestCase
  setup do
    @command_event = command_events(:one)
  end

  test "visiting the index" do
    visit command_events_url
    assert_selector "h1", text: "Command Events"
  end

  test "creating a Command event" do
    visit command_events_url
    click_on "New Command Event"

    fill_in "Client", with: @command_event.client_id
    fill_in "Duration", with: @command_event.duration
    fill_in "Macos version", with: @command_event.macos_version
    fill_in "Name", with: @command_event.name
    fill_in "Params", with: @command_event.params
    fill_in "Subcommand", with: @command_event.subcommand
    fill_in "Swift version", with: @command_event.swift_version
    fill_in "Tuist version", with: @command_event.tuist_version
    click_on "Create Command event"

    assert_text "Command event was successfully created"
    click_on "Back"
  end

  test "updating a Command event" do
    visit command_events_url
    click_on "Edit", match: :first

    fill_in "Client", with: @command_event.client_id
    fill_in "Duration", with: @command_event.duration
    fill_in "Macos version", with: @command_event.macos_version
    fill_in "Name", with: @command_event.name
    fill_in "Params", with: @command_event.params
    fill_in "Subcommand", with: @command_event.subcommand
    fill_in "Swift version", with: @command_event.swift_version
    fill_in "Tuist version", with: @command_event.tuist_version
    click_on "Update Command event"

    assert_text "Command event was successfully updated"
    click_on "Back"
  end

  test "destroying a Command event" do
    visit command_events_url
    page.accept_confirm do
      click_on "Destroy", match: :first
    end

    assert_text "Command event was successfully destroyed"
  end
end
