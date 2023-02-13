# frozen_string_literal: true

require "test_helper"

class LastVisitedProjectUpdateServiceTest < ActiveSupport::TestCase
  test "updates a last visited project to a given id when current is nil" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    project = Project.create!(
      name: "tuist-project",
      account_id: user.account.id,
      token: Devise.friendly_token.first(16))

    # When
    got = LastVisitedProjectUpdateService.call(id: project.id, user: user)

    # Then
    assert_equal got.last_visited_project_id, project.id
  end

  test "updates a last visited project to a given id when current is an existing project" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    project_one = Project.create!(
      name: "tuist-project-one",
      account_id: user.account.id,
      token: Devise.friendly_token.first(16))
    project_two = Project.create!(
      name: "tuist-project-two",
      account_id: user.account.id,
      token: Devise.friendly_token.first(16))
    LastVisitedProjectUpdateService.call(id: project_one.id, user: user)

    # When
    got = LastVisitedProjectUpdateService.call(id: project_two.id, user: user)

    # Then
    assert_equal got.last_visited_project_id, project_two.id
  end
end
