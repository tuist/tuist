class CreateQueSchedulerSchema < ActiveRecord::Migration[7.1]
  def change
    Que::Scheduler::Migrations.migrate!(version: 7)
  end
end
