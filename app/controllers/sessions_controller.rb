class SessionsController < ApplicationController
  def create
    auth = request.env['omniauth.auth']
    
    begin
      access_token = AccessToken.find_or_initialize_by(ghId: auth.uid)
      access_token.assign_attributes(
        username: auth.info.nickname,
        accessToken: auth.credentials.token
      )

      if access_token.save
        # Initialize rate limits using the token
        client = access_token.client
        
        begin
          # Get REST API rate limits
          rest_limits = client.rate_limit
          core_limits = rest_limits.resources.core
          search_limits = rest_limits.resources.search
          
          # Get GraphQL API rate limit
          graphql_query = '{ rateLimit { remaining resetAt } }'
          graphql_response = client.post('/graphql', { query: graphql_query }.to_json)
          graphql_limits = graphql_response.data.rate_limit
          
          # Update all rate limits
          access_token.update_rate_limits(
            core: { remaining: core_limits.remaining, reset: core_limits.resets_at.to_i },
            search: { remaining: search_limits.remaining, reset: search_limits.resets_at.to_i },
            graphql: { 
              remaining: graphql_limits.remaining,
              reset: Time.parse(graphql_limits.reset_at).to_i
            }
          )

          flash[:success] = 'Thanks for donating your GitHub token! It will be used to gather Hack Club statistics.'
        rescue Octokit::Error => e
          # If we can't get rate limits, still save the token but show a warning
          flash[:warning] = 'Token saved, but there was an issue checking rate limits. This will be resolved automatically.'
        end
      else
        flash[:error] = 'There was an error saving your GitHub token.'
      end
    rescue => e
      Rails.logger.error("Error in OAuth callback: #{e.message}")
      flash[:error] = 'There was an unexpected error processing your GitHub login.'
    end

    redirect_to root_path
  end

  def failure
    Rails.logger.error("OAuth failure: #{params[:message]}")
    flash[:error] = 'Failed to authenticate with GitHub. Please try again.'
    redirect_to root_path
  end
end 