# frozen_string_literal: true

Rolify.configure do |config|
  # By default ORM adapter is ActiveRecord. uncomment to use mongoid
  # config.use_mongoid

  # Dynamic shortcuts for User class (user.is_admin? like methods). Default is: false
  # config.use_dynamic_shortcuts

  # Configuration to remove roles from database once the last resource is removed. Default is: true
  # config.remove_role_if_empty = false
end
