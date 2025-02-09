class GhOrg < ApplicationRecord
  has_many :gh_repos
  has_and_belongs_to_many :gh_users

  validates :gh_id, presence: true, uniqueness: true
  validates :name, presence: true, uniqueness: true
end
