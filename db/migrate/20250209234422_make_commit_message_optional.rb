class MakeCommitMessageOptional < ActiveRecord::Migration[8.0]
  def change
    change_column_null :commits, :message, true
  end
end
