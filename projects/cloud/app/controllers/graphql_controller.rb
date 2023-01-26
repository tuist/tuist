# frozen_string_literal: true

class GraphqlController < APIController
  # If accessing from outside this domain, nullify the session
  # This allows for outside API access while preventing CSRF attacks,
  # but you'll have to authenticate your user separately
  # protect_from_forgery with: :null_session
  skip_before_action :authenticate_user_from_token!

  def execute
    if current_user.nil?
      begin
        authenticate_user_from_token!
      rescue
        url = "#{Rails.application.config.defaults[:urls][:app]}#{user_session_path}"
        error_message = "Authentication is required to interact with the GraphQL API. Authenticate through #{url}"
        error_extensions = { code: "AUTHENTICATION_ERROR" }
        raise GraphQL::ExecutionError.new(error_message, extensions: error_extensions)
      end
    end

    variables = prepare_variables(params[:variables])
    query = params[:query]
    operation_name = params[:operationName]
    context = {
      current_user: current_user,
    }
    result = TuistCloudSchema.execute(query, variables: variables, context: context, operation_name: operation_name)
    render(json: result)
  rescue StandardError => error
    unless Rails.env.development?
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: :internal_server_error })
    end

    handle_error_in_development(error)
  end

  private
    # Handle variables in form data, JSON body, or a blank value
    def prepare_variables(variables_param)
      case variables_param
      when String
        if variables_param.present?
          JSON.parse(variables_param) || {}
        else
          {}
        end
      when Hash
        variables_param
      when ActionController::Parameters
        variables_param.to_unsafe_hash # GraphQL-Ruby will validate name and type of incoming variables.
      when nil
        {}
      else
        raise ArgumentError, "Unexpected parameter: #{variables_param}"
      end
    end

    def handle_error_in_development(e)
      logger.error(e.message)
      logger.error(e.backtrace.join("\n"))

      render(
        json: { errors: [{ message: e.message, backtrace: e.backtrace }], data: {} },
        status: :internal_server_error)
    end
end
