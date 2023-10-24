# frozen_string_literal: true

# lib/warden/token_authenticatable.rb

Warden::Strategies.add(:project_token_authenticatable) do
  def valid?
    authorization_header.present?
  end

  def authenticate!
    Rails.logger.info "Attempting project authentication"
    project = Project.find_by(token: bearer_token)

    if project
      success!(project, store: false)
    else
      Rails.logger.info "Project authentication failed"
      pass()
    end
  end

  def bearer_token
    pattern = /^Bearer /
    header = authorization_header
    header.gsub(pattern, '') if header&.match(pattern)
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
    Rails.logger.info "Attempting user authentication"
    user = User.find_by(token: bearer_token)

    if user
      success!(user, store: false)
    else
      Rails.logger.info "User authentication failed"
      pass()
    end
  end

  def bearer_token
    pattern = /^Bearer /
    header = authorization_header
    header.gsub(pattern, '') if header&.match(pattern)
  end

  def authorization_header
    @authorization_header ||= env['HTTP_AUTHORIZATION']
  end
end
