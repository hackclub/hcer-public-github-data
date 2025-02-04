class SessionsController < ApplicationController
  def create
    auth = request.env['omniauth.auth']

    access_token = AccessToken.find_or_initialize_by(gh_id: auth.uid)

    access_token.assign_attributes(
      username: auth.info.nickname,
      access_token: auth.credentials.token
    )

    access_token.assign_rate_limits_from_api

    if access_token.save
      flash[:success] = 'Thanks for donating your GitHub token! It will be used to gather Hack Club statistics.'
    else
      flash[:error] = 'There was an error saving your GitHub token.'
    end

  rescue StandardError => e
    Rails.logger.error("Error in OAuth callback: #{e.message}")
    flash[:error] = 'There was an unexpected error processing your GitHub login.'
  ensure
    redirect_to root_path
  end

  def failure
    Rails.logger.error("OAuth failure: #{params[:message]}")
    flash[:error] = 'Failed to authenticate with GitHub. Please try again.'
    redirect_to root_path
  end
end 