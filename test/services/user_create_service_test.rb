# frozen_string_literal: true

require "test_helper"

class UserCreateServiceTest < ActiveSupport::TestCase
  def test_returns_the_user
    # Given
    email = "test@cloud.tuist.io"
    password = "123456"
    id_in_provider = "5678"
    provider = :github

    # When
    got = UserCreateService.call(email: email, id_in_provider: id_in_provider, provider: provider)

    # Then
    assert_equal(email, got.email)
    assert_not_equal(password, "")
    assert(got.account)
    assert(got.oauth2_identities.first.id_in_provider, id_in_provider)
    assert_equal("test", got.account.name)
  end

  def test_returns_the_user_if_it_already_exists
    # Given
    email = "test@cloud.tuist.io"
    id_in_provider = "5678"
    provider = :github

    # When
    first_user = UserCreateService.call(email: email, id_in_provider: id_in_provider, provider: provider)
    second_user = UserCreateService.call(email: email, id_in_provider: id_in_provider, provider: provider)

    # Then
    assert_equal(second_user, first_user)
  end

  def test_adds_the_oauth2_identity_if_a_user_exists_without_it
    # Given
    email = "test@cloud.tuist.io"
    id_in_provider = "5678"
    provider = :github
    user = User.create(email: email, password: "123456")

    # # When
    got = UserCreateService.call(email: user.email, id_in_provider: id_in_provider, provider: provider)

    # # Then
    assert_equal(got, user)
    assert_equal(got.oauth2_identities.count, 1)
    assert_equal(got.oauth2_identities.first.provider.to_sym, provider)
    assert_equal(got.oauth2_identities.first.id_in_provider, id_in_provider)
  end

  def test_changes_the_account_name_if_another_user_with_the_same_account_name_exists
    # Given
    provider = :github

    # When
    UserCreateService.call(email: "test@cloud.tuist.io", id_in_provider: "5678", provider: provider)
    user = UserCreateService.call(email: "test@tuist.io", id_in_provider: "9012", provider: provider)

    # Then
    assert_equal("test1", user.account.name)
  end
end
