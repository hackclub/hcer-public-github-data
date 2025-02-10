class TrackedGhUser < ApplicationRecord
  validates :username, presence: true, uniqueness: true
  validates :gh_id, uniqueness: { allow_nil: true }
  validate :must_be_user_not_org

  before_save :ensure_tags_array

  # Add association to GhUser
  belongs_to :gh_user, foreign_key: :gh_id, primary_key: :gh_id, optional: true
  
  # Delegate scrape_last_completed_at to the associated gh_user
  delegate :scrape_last_completed_at, to: :gh_user, allow_nil: true

  private

  def ensure_tags_array
    self.tags ||= []
  end

  def must_be_user_not_org
    return unless gh_id.present?
    
    begin
      user_data = GhApi::Client.request("users/#{username}")
      if user_data[:type] == 'Organization'
        errors.add(:base, "#{username} is an organization, not a user")
      end
    rescue GhApi::NotFoundError
      errors.add(:base, "#{username} not found on GitHub")
    rescue GhApi::RateLimitError
      errors.add(:base, "Rate limit exceeded, try again later")
    rescue GhApi::NoAvailableTokensError
      errors.add(:base, "No available GitHub tokens")
    rescue => e
      errors.add(:base, "Error checking user type: #{e.message}")
    end
  end
end
