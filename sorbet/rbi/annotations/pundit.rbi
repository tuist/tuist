# typed: true

# DO NOT EDIT MANUALLY
# This file was pulled from a central RBI files repository.
# Please run `bin/tapioca annotations` to update it.

module Pundit::Authorization
  sig { void }
  def skip_authorization; end

  sig { void }
  def skip_policy_scope; end
end
