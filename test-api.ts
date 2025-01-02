import { GitHubAPI } from './src/github';

async function main() {
  const github = new GitHubAPI();

  try {
    // Test 1: Get rate limit info
    console.log('\n=== Test 1: Rate Limits ===');
    const rateLimit = await github.request({
      url: '/rate_limit'
    });
    console.log('Rate Limit Request ID:', rateLimit.requestId);
    console.log('Rate Limits:', JSON.stringify(rateLimit.data, null, 2));

    // Test 2: Get authenticated user info
    console.log('\n=== Test 2: User Info ===');
    const userInfo = await github.request({
      url: '/user'
    });
    console.log('User Info Request ID:', userInfo.requestId);
    console.log('User Info:', JSON.stringify(userInfo.data, null, 2));

    // Test 3: List first 3 repositories
    console.log('\n=== Test 3: Repositories ===');
    const repos = await github.request({
      url: '/user/repos',
      params: {
        per_page: 3,
        sort: 'updated'
      }
    });
    console.log('Repos Request ID:', repos.requestId);
    console.log('First 3 repos:', repos.data.map(repo => ({
      name: repo.name,
      private: repo.private,
      updated_at: repo.updated_at
    })));

  } catch (error) {
    if (error instanceof Error) {
      console.error('Error:', error.message);
      console.error('Stack:', error.stack);
    } else {
      console.error('Unknown error:', error);
    }
  }
}

main(); 