module GhApi
  class Error < StandardError; end
  class RateLimitError < Error; end
  class NotFoundError < Error; end
  class EmptyRepoError < Error; end
  class NoAvailableTokensError < Error; end
  class DMCATakedownError < Error; end

  class Client
    CACHE_VERSION = 'v1'
    CACHE_EXPIRATION = 1.day
    MAX_RETRIES = 3

    def self.request(path, params = {})
      query = params.empty? ? '' : "?#{params.to_query}"
      full_path = "#{path}#{query}"
      api_type = determine_api_type(path)
      
      Rails.cache.fetch(cache_key(full_path, api_type), expires_in: CACHE_EXPIRATION) do
        make_request(path, params, api_type)
      end
    end

    def self.request_paginated(path, params = {})
      results = []
      page = 1

      loop do
        page_params = params.merge(page: page, per_page: 100)
        page_data = request(path, page_params)
        
        break if page_data.empty?
        
        results.concat(page_data)
        break if page_data.length < 100
        
        page += 1
      end

      results
    end

    private

    def self.make_request(path, params, api_type, retry_count = 0)
      token = AccessToken.find_available_token(api_type)
      raise NoAvailableTokensError, 'No available tokens' unless token

      token.with_lock do
        begin
          response = token.client.get(path, params)
          update_token_rate_limits(token, api_type)
          response.is_a?(Array) ? response.map { |item| item.to_hash.deep_symbolize_keys } : response.to_hash.deep_symbolize_keys
        rescue Octokit::NotFound
          raise NotFoundError, "GitHub resource not found: #{path}"
        rescue Octokit::Unauthorized
          Rails.logger.warn "Token #{token.username} is unauthorized. Revoking..."
          token.revoke!
          
          if retry_count < MAX_RETRIES
            Rails.logger.info "Retrying request with a new token (attempt #{retry_count + 1}/#{MAX_RETRIES})"
            make_request(path, params, api_type, retry_count + 1)
          else
            raise Error, "Failed to find a working token after #{MAX_RETRIES} attempts"
          end
        rescue Octokit::Error => e
          token.assign_rate_limits_from_api
          token.save!
          
          if e.response_status == 403 && e.message.include?('rate limit')
            raise RateLimitError, "Rate limit exceeded for path: #{path}"
          elsif e.response_status == 409 && path.include?('/commits')
            # Return empty array for empty repositories
            []
          elsif e.response_status == 451
            raise DMCATakedownError, "Repository unavailable due to DMCA takedown: #{path}"
          else
            raise Error, "GitHub API error (#{e.response_status}): #{e.message}"
          end
        end
      end
    end

    def self.determine_api_type(path)
      if path.start_with?('search')
        :search
      elsif path.start_with?('graphql')
        :graphql
      else
        :core
      end
    end

    def self.cache_key(full_path, api_type)
      key_parts = [
        'github_api',
        CACHE_VERSION,
        api_type,
        Digest::SHA256.hexdigest(full_path)
      ]
      key_parts.join('/')
    end

    def self.update_token_rate_limits(token, api_type)
      rl = token.client.rate_limit

      token.send("#{api_type}_rate_limit_remaining=", rl.remaining)
      token.send("#{api_type}_rate_limit_reset_at=", rl.resets_at)
      token.save!
    end
  end
end 