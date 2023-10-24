# frozen_string_literal: true

# lib/warden/token_authenticatable.rb

Warden::Strategies.add(:project_token_authenticatable) do
  def valid?
    authorization_header.present?
  end

  def authenticate!
    token = authorization_header.split(' ').last
    project = Project.find_by(token: token)

    if project
      success!(project)
    else
      pass()
    end
  end

  def authorization_header
    @authorization_header ||= env['HTTP_AUTHORIZATION']
  end
end

Warden::Strategies.add(:user_token_authenticatable) do
  def valid?
    authorization_header.present?
  end

  def authenticate!
    token = authorization_header.split(' ').last
    user = User.find_by(token: token)

    if user
      success!(user)
    else
      pass()
    end
  end

  def authorization_header
    @authorization_header ||= env['HTTP_AUTHORIZATION']
  end
end
