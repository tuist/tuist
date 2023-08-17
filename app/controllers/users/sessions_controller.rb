# frozen_string_literal: true

module Users
  class SessionsController < Devise::SessionsController
    def after_sign_in_path_for(resource)
      if session["is_cli_authenticating"]
        redirect_to(
          "http://127.0.0.1:4545/auth?token=#{current_user.token}&account=#{current_user.account.name}",
          allow_other_host: true
        )
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
