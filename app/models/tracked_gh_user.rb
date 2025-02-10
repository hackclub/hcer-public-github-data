class TrackedGhUser < ApplicationRecord
  validates :username, presence: true, uniqueness: true
  validates :gh_id, uniqueness: { allow_nil: true }

  before_save :ensure_tags_array

  # Add association to GhUser
  belongs_to :gh_user, foreign_key: :gh_id, primary_key: :gh_id, optional: true
  
  # Delegate scrape_last_completed_at to the associated gh_user
  delegate :scrape_last_completed_at, to: :gh_user, allow_nil: true

  private

  def ensure_tags_array
    self.tags ||= []
  end
end
