require "test_helper"

class TrackedGhUsersControllerTest < ActionDispatch::IntegrationTest
  test "should get new" do
    get new_admin_tracked_gh_user_url, headers: auth_headers
    assert_response :success
  end

  test "should enqueue tracked users creation" do
    assert_enqueued_with(job: AddTrackedUsersJob, args: [ [ "octocat", "hubot" ], [ "ruby", "rails" ] ]) do
      post admin_tracked_gh_users_url,
        params: {
          usernames: "octocat\nhubot",
          tags: [ "ruby" ],
          new_tags: "rails"
        },
        headers: auth_headers
    end

    assert_redirected_to admin_tracked_gh_users_url
    assert_equal "Processing 2 usernames in the background. Check back soon to see the results.", flash[:notice]
  end

  test "should re-render new when no usernames are provided" do
    post admin_tracked_gh_users_url,
      params: { usernames: "", tags: [], new_tags: "" },
      headers: auth_headers

    assert_response :success
    assert_equal "Please enter at least one username", flash[:alert]
  end

  private

  def auth_headers
    {
      "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(
        "test",
        ENV.fetch("PROXY_API_KEY")
      )
    }
  end
end
