module Api
  class ApplicationController < ::ApplicationController
    skip_before_action :verify_authenticity_token
    
    # Common error handling for API controllers
    rescue_from ActiveRecord::RecordNotFound, with: :not_found
    
    private
    
    def not_found(exception = nil)
      message = exception&.message || "Resource not found"
      render plain: message, status: :not_found
    end
  end
end 