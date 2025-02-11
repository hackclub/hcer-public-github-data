module TrackedGhUsersHelper
  def scrape_status_badge(user)
    if user.scrape_last_completed_at.nil?
      content_tag :span, "Never Scraped", class: "status-badge warning"
    elsif user.scrape_last_completed_at < 24.hours.ago
      content_tag :span, "Needs Update", class: "status-badge error"
    else
      content_tag :span, "Up to Date", class: "status-badge success"
    end
  end

  def recently_requested?(user)
    user.scrape_last_requested_at && user.scrape_last_requested_at > 5.minutes.ago
  end
end
