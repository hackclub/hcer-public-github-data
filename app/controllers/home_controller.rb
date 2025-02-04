class HomeController < ApplicationController
  def index
    @access_tokens_count = AccessToken.count
    
    if latest_token = AccessToken.order(created_at: :desc).first
      @latest_donor = latest_token.username
      @latest_donation_time = latest_token.created_at
    end
  end
end 