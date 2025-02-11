class GhRepo < ApplicationRecord
  belongs_to :gh_user, optional: true
  belongs_to :gh_org, optional: true
  has_and_belongs_to_many :gh_commits

  validates :gh_id, presence: true, uniqueness: true
  validates :name, presence: true
  validate :must_belong_to_user_or_org

  # Scopes for common queries
  scope :active, -> { where(archived: false, disabled: false) }
  scope :public_repos, -> { where(private: false) }
  scope :by_language, ->(language) { where(language: language) }
  scope :popular, -> { order(stargazers_count: :desc) }
  scope :recently_pushed, -> { order(pushed_at: :desc) }
  scope :non_forks, -> { where(fork: false) }

  def owner_gh_username
    gh_user.present? ? gh_user.username : gh_org.name
  end

  private

  def must_belong_to_user_or_org
    if gh_user.nil? && gh_org.nil?
      errors.add(:base, 'Repository must belong to either a user or an organization')
    end
  end
end
