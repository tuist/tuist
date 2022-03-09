# frozen_string_literal: true

module Users
  class SessionsController < Devise::SessionsController
    def new
      puts "new"
      puts resource
      # @resource.email = "marekfort9@gmail.com"
      # @resource.password = "123456"
      super
    end

    protected
      def respond_to_on_destroy
        head(:no_content)
      end
  end
end
