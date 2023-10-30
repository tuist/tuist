# frozen_string_literal: true

require "test_helper"

class ProjectFetchServiceTest < ActiveSupport::TestCase
  test "fetches a project with a given name account_name" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    account = user.account
    Project.create!(name: "tuist-project", account_id: account.id, token: Devise.friendly_token.first(16))
    project = Project.create!(name: "tuist-project-2", account_id: account.id, token: Devise.friendly_token.first(16))

    # When
    got = ProjectFetchService.new.fetch_by_name(name: project.name, account_name: account.name, subject: user)

    # Then
    assert_equal project, got
  end

  test "fetches a project with a given project slug" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    account = user.account
    Project.create!(name: "tuist-project", account_id: account.id, token: Devise.friendly_token.first(16))
    project = Project.create!(name: "tuist-project-2", account_id: account.id, token: Devise.friendly_token.first(16))

    # When
    got = ProjectFetchService.new.fetch_by_slug(slug: "test/tuist-project-2", subject: user)

    # Then
    assert_equal project, got
  end

  test "fails to fetch a project if user does not have rights to access it" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    organization = Organization.create!
    account = Account.create!(owner: organization, name: "tuist")
    Project.create!(name: "tuist-project", account_id: account.id, token: Devise.friendly_token.first(16))
    project = Project.create!(name: "tuist-project-2", account_id: account.id, token: Devise.friendly_token.first(16))

    # When / Then
    assert_raises(ProjectFetchService::Error::Unauthorized) do
      ProjectFetchService.new.fetch_by_name(name: project.name, account_name: account.name, subject: user)
    end
  end

  test "fails with project not found if the project does not exist" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    organization = Organization.create!
    account = Account.create!(owner: organization, name: "tuist")

    # When / Then
    assert_raises(ProjectFetchService::Error::ProjectNotFoundByName) do
      ProjectFetchService.new.fetch_by_name(name: "non-existent-name", account_name: account.name, subject: user)
    end
  end

  test "fails with project not found if the project with the given id does not exist" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))

    # When / Then
    assert_raises(ProjectFetchService::Error::ProjectNotFoundById) do
      ProjectFetchService.new.fetch_by_id(project_id: 2, subject: user)
    end
  end

  test "fetches a project with a given id" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    organization = Organization.create!
    account = Account.create!(owner: organization, name: "tuist")
    project = Project.create!(name: "tuist-project", account_id: account.id, token: Devise.friendly_token.first(16))
    user.add_role(:user, organization)

    # When
    got = ProjectFetchService.new.fetch_by_id(project_id: project.id, subject: user)

    # Then
    assert_equal project, got
  end

  test "fails with account not found when account does not exist" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))

    # When / Then
    assert_raises(AccountFetchService::Error::AccountNotFound) do
      ProjectFetchService.new.fetch_by_name(name: "tuist", account_name: "tuist", subject: user)
    end
  end
end
