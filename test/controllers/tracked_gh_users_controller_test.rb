require "test_helper"

class TrackedGhUsersControllerTest < ActionDispatch::IntegrationTest
  test "should get new" do
    get tracked_gh_users_new_url
    assert_response :success
  end

  test "should get create" do
    get tracked_gh_users_create_url
    assert_response :success
  end
end
