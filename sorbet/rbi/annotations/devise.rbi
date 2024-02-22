# typed: true

# DO NOT EDIT MANUALLY
# This file was pulled from a central RBI files repository.
# Please run `bin/tapioca annotations` to update it.

# @shim: Devise controllers are loaded by rails
class DeviseController
  sig { returns(T.untyped) }
  def resource; end

  # Proxy to devise map name
  sig { returns(String) }
  def resource_name; end

  sig { returns(String) }
  def scope_name; end

  # Proxy to devise map class
  sig { returns(T::Class[T.anything]) }
  def resource_class; end

  # Returns a signed in resource from session (if one exists)
  sig { returns(T.untyped) }
  def signed_in_resource; end

  # Attempt to find the mapped route for devise based on request path
  sig { returns(T.untyped) }
  def devise_mapping; end

  sig { returns(T.untyped) }
  def navigational_formats; end

  sig { returns(ActionController::Parameters) }
  def resource_params; end

  sig { returns(String) }
  def translation_scope; end
end

# @shim: Devise controllers are loaded by rails
class Devise::ConfirmationsController < DeviseController
  sig { returns(T.untyped) }
  def new; end

  # POST /resource/confirmation
  sig { returns(T.untyped) }
  def create; end

  # GET /resource/confirmation?confirmation_token=abcdef
  sig { returns(T.untyped) }
  def show; end
end

# @shim: Devise controllers are loaded by rails
class Devise::PasswordsController < DeviseController
  # GET /resource/password/new
  sig { returns(T.untyped) }
  def new; end

  # POST /resource/password
  sig { returns(T.untyped) }
  def create; end

  # GET /resource/password/edit?reset_password_token=abcdef
  sig { returns(T.untyped) }
  def edit; end

  # PUT /resource/password
  sig { returns(T.untyped) }
  def update; end
end

# @shim: Devise controllers are loaded by rails
class Devise::RegistrationsController < DeviseController
  sig { returns(T.untyped) }
  def new; end

  # POST /resource
  sig { returns(T.untyped) }
  def create; end

  # GET /resource/edit
  sig { returns(T.untyped) }
  def edit; end

  # PUT /resource
  # We need to use a copy of the resource because we don't want to change
  # the current user in place.
  sig { returns(T.untyped) }
  def update; end

  # DELETE /resource
  sig { returns(T.untyped) }
  def destroy; end

  # GET /resource/cancel
  # Forces the session data which is usually expired after sign
  # in to be expired now. This is useful if the user wants to
  # cancel oauth signing in/up in the middle of the process,
  # removing all OAuth session data.
  sig { returns(T.untyped) }
  def cancel; end
end

# @shim: Devise controllers are loaded by rails
class Devise::SessionsController < DeviseController
  # GET /resource/sign_in
  sig { returns(T.untyped) }
  def new; end

  # POST /resource/sign_in
  sig { returns(T.untyped) }
  def create; end

  # DELETE /resource/sign_out
  sig { returns(T.untyped) }
  def destroy; end

  sig { returns(ActionController::Parameters) }
  def sign_in_params; end
end

# @shim: Devise controllers are loaded by rails
class Devise::UnlocksController < DeviseController
  # GET /resource/unlock/new
  sig { returns(T.untyped) }
  def new; end

  # POST /resource/unlock
  sig { returns(T.untyped) }
  def create; end

  # GET /resource/unlock?unlock_token=abcdef
  sig { returns(T.untyped) }
  def show; end

  # The path used after sending unlock password instructions
  sig { params(resource: T.untyped).returns(String) }
  def after_sending_unlock_instructions_path_for(resource); end

  # The path used after unlocking the resource
  sig { params(resource: T.untyped).returns(String) }
  def after_unlock_path_for(resource); end
end
