class HomeController < ApplicationController
  def index
    @access_tokens_count = AccessToken.count
  end
end 