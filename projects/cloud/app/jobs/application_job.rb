# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  include Bullet::ActiveJob if Rails.env.development?

  retry_on ActiveRecord::Deadlocked
end
