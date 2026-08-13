require "test_helper"

class HomeTest < ActionDispatch::IntegrationTest
  test "directs visitors to the replacement service and disables donations" do
    get root_url

    assert_response :success
    assert_select ".migration-banner a[href='https://gh-proxy.hackclub.com/']"
    assert_select "button.donate-button[disabled]", text: "Donate Token"
    assert_select "form[action='/auth/github']", count: 0
  end
end
