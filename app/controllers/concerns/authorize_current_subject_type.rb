# frozen_string_literal: true

module AuthorizeCurrentSubjectType
  extend ActiveSupport::Concern

  module Error
    class Unauthorized < CloudError
      def message
        "The authenticated subject is either invalid or doesn't have access to this resource."\
          " Note that some subjects, like projects, have limited access to resources."
      end

      def status_code
        :unauthorized
      end
    end
  end

  included do
    before_action :authorize_current_subject!
  end

  class_methods do
    def authorize_current_subject_type(actions = {})
      @subject_type_permissions = actions
    end

    def subject_type_permissions
      @subject_type_permissions || {}
    end
  end

  private

  def authorize_current_subject!
    action = action_name.to_sym
    return unless self.class.subject_type_permissions[action]

    allowed_subject_types = self.class.subject_type_permissions[action]
    unless allowed_subject_types.include?(current_subject.class.name.downcase.to_sym)
      raise Error::Unauthorized
    end
  end
end
