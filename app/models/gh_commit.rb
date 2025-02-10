class GhCommit < ApplicationRecord
  belongs_to :gh_user
  has_and_belongs_to_many :gh_repos

  validates :sha, presence: true
  validates :committed_at, presence: true
end
