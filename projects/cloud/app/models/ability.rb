class Ability
  include CanCan::Ability

  def initialize(user)
    can :read, Organization do |organization|
      user.roles.find_by(resource_type: :Organization, resource_id: organization.id).name == "user"
    end

    can [:read, :write], Organization do |organization|
      user.roles.find_by(resource_type: :Organization, resource_id: organization.id).name == "admin"
    end

    can [:read], Project do |project|
      user_role = user.roles.find_by(resource_type: project.account.owner_type, resource_id: project.account.owner_id)
      !user_role.nil? && user_role.name == "user"
    end

    can [:read, :write], Project, { account: { owner: user } }
    can [:read, :write], Project do |project|
      user_role = user.roles.find_by(resource_type: project.account.owner_type, resource_id: project.account.owner_id)
      !user_role.nil? && user_role.name == "admin"
    end

    # Define abilities for the passed in user here. For example:
    #
    #   user ||= User.new # guest user (not logged in)
    #   if user.admin?
    #     can :manage, :all
    #   else
    #     can :read, :all
    #   end
    #
    # The first argument to `can` is the action you are giving the user
    # permission to do.
    # If you pass :manage it will apply to every action. Other common actions
    # here are :read, :create, :update and :destroy.
    #
    # The second argument is the resource the user can perform the action on.
    # If you pass :all it will apply to every resource. Otherwise pass a Ruby
    # class of the resource.
    #
    # The third argument is an optional hash of conditions to further filter the
    # objects.
    # For example, here the user can only update published articles.
    #
    #   can :update, Article, :published => true
    #
    # See the wiki for details:
    # https://github.com/ryanb/cancan/wiki/Defining-Abilities
  end
end
