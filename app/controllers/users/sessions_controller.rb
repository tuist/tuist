# frozen_string_literal: true

module Users
  class SessionsController < Devise::SessionsController
    def after_sign_in_path_for(resource)
      if session["is_cli_authenticating"]
        '/auth/cli/success'
      else
        root_path
      end
    end

    protected
      def respond_to_on_destroy
        head(:no_content)
      end
  end
end
