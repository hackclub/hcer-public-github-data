class GhRepo < ApplicationRecord
  belongs_to :gh_user, optional: true
  belongs_to :gh_org, optional: true
  has_and_belongs_to_many :commits

  validates :gh_id, presence: true, uniqueness: true
  validates :name, presence: true
  validate :must_belong_to_user_or_org

  private

  def must_belong_to_user_or_org
    if gh_user.nil? && gh_org.nil?
      errors.add(:base, 'Repository must belong to either a user or an organization')
    end
  end
end
