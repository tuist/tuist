# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# Specify a serializer for the signed and encrypted cookie jars.
# Valid options are :json, :marshal, and :hybrid.
Rails.application.config.action_dispatch.cookies_serializer = :json

Rails.application.config.session_store(:cookie_store, key: '_tuist_cloud_session')
Rails.application.config.action_dispatch.cookies_serializer = :json

# These salts are optional, but it doesn't hurt to explicitly configure them the same between the two apps.
Rails.application.config.action_dispatch.encrypted_cookie_salt = "salt"
Rails.application.config.action_dispatch.encrypted_signed_cookie_salt = "salt"
