class GhUser < ApplicationRecord
  has_many :gh_repos
  has_many :commits
  has_and_belongs_to_many :gh_orgs

  validates :gh_id, presence: true, uniqueness: true
  validates :username, presence: true, uniqueness: true
end
