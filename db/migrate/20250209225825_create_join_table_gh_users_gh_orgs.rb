class CreateJoinTableGhUsersGhOrgs < ActiveRecord::Migration[8.0]
  def change
    create_join_table :gh_users, :gh_orgs do |t|
      t.index [:gh_user_id, :gh_org_id], unique: true
      t.index [:gh_org_id, :gh_user_id]
    end
  end
end
