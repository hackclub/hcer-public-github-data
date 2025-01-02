import { PrismaClient } from '@prisma/client';
import { Octokit } from 'octokit';
import { GitHubAPI } from './src/github';
import { GitHubScraper } from './src/scraper';

const prisma = new PrismaClient();
const github = new GitHubAPI();
const scraper = new GitHubScraper();
const port = 3000;

// GitHub OAuth configuration
const GITHUB_CLIENT_ID = process.env.GITHUB_CLIENT_ID || '';
const GITHUB_CLIENT_SECRET = process.env.GITHUB_CLIENT_SECRET || '';
const REDIRECT_URI = `http://localhost:${port}/auth/github/callback`;

interface GitHubOAuthResponse {
  access_token: string;
  refresh_token?: string;
  expires_in: number;
  refresh_token_expires_in?: number;
  scope: string;
  token_type: string;
}

async function addGitHubUser(username: string): Promise<{ success: boolean; message: string }> {
  try {
    // Check if user already exists
    const existingUser = await prisma.gitHubUser.findUnique({
      where: { login: username }
    });

    if (existingUser) {
      return { success: false, message: `User ${username} already exists` };
    }

    // Fetch user data from GitHub
    const { data: userData, requestId } = await github.request({
      url: `/users/${username}`
    });

    // Store in database
    await prisma.gitHubUser.create({
      data: {
        id: userData.id,
        login: userData.login,
        name: userData.name || null,
        email: userData.email || null,
        bio: userData.bio || null,
        location: userData.location || null,
        websiteUrl: userData.blog || null,
        avatarUrl: userData.avatar_url || null,
        followers: userData.followers || 0,
        following: userData.following || 0,
        fetchedFromRequestId: requestId
      }
    });

    return { success: true, message: `Added user ${username}` };
  } catch (error) {
    console.error('Error adding user:', username, error);
    return { success: false, message: `Failed to add user ${username}: ${error instanceof Error ? error.message : 'Unknown error'}` };
  }
}

const server = Bun.serve({
  port,
  async fetch(req) {
    const url = new URL(req.url);

    // Health check
    if (url.pathname === '/health') {
      return new Response('OK');
    }

    // GitHub OAuth initialization
    if (url.pathname === '/auth/github') {
      const state = crypto.randomUUID(); // CSRF protection
      const githubAuthUrl = new URL('https://github.com/login/oauth/authorize');
      githubAuthUrl.searchParams.set('client_id', GITHUB_CLIENT_ID);
      githubAuthUrl.searchParams.set('redirect_uri', REDIRECT_URI);
      githubAuthUrl.searchParams.set('state', state);

      return new Response(null, {
        status: 302,
        headers: {
          'Location': githubAuthUrl.toString(),
          'Set-Cookie': `oauth_state=${state}; HttpOnly; Path=/; SameSite=Lax`
        }
      });
    }

    // GitHub OAuth callback
    if (url.pathname === '/auth/github/callback') {
      const code = url.searchParams.get('code');
      const state = url.searchParams.get('state');
      const cookieHeader = req.headers.get('cookie');
      const cookies = Object.fromEntries(
        cookieHeader?.split(';').map(cookie => {
          const [key, value] = cookie.trim().split('=');
          return [key, value];
        }) || []
      );

      // Verify state to prevent CSRF
      if (!state || !cookies.oauth_state || state !== cookies.oauth_state) {
        return new Response('Invalid state', { status: 403 });
      }

      if (!code) {
        return new Response('No code provided', { status: 400 });
      }

      try {
        // Exchange code for tokens
        const tokenResponse = await fetch('https://github.com/login/oauth/access_token', {
          method: 'POST',
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            client_id: GITHUB_CLIENT_ID,
            client_secret: GITHUB_CLIENT_SECRET,
            code,
            redirect_uri: REDIRECT_URI,
          }),
        });

        if (!tokenResponse.ok) {
          throw new Error('Failed to exchange code for token');
        }

        const tokenData = await tokenResponse.json() as GitHubOAuthResponse;
        
        // Get user information using the token
        const octokit = new Octokit({ auth: tokenData.access_token });
        const { data: userData } = await octokit.rest.users.getAuthenticated();

        // Calculate token expiry
        const tokenExpiry = new Date();
        tokenExpiry.setSeconds(tokenExpiry.getSeconds() + (tokenData.expires_in || 28800)); // Default to 8 hours if not provided

        // Store access token in database
        const token = await prisma.accessToken.upsert({
          where: { githubId: userData.id },
          update: {
            username: userData.login,
            accessToken: tokenData.access_token,
            refreshToken: tokenData.refresh_token,
            tokenExpiry,
          },
          create: {
            githubId: userData.id,
            username: userData.login,
            accessToken: tokenData.access_token,
            refreshToken: tokenData.refresh_token,
            tokenExpiry,
          },
        });

        // Return success page
        return new Response(`
          <!DOCTYPE html>
          <html>
            <head>
              <title>Success!</title>
            </head>
            <body>
              <h1>Success!</h1>
              <p>Thank you for donating your GitHub token, ${userData.login}!</p>
              <p>Your token has been stored securely.</p>
            </body>
          </html>
        `, {
          headers: {
            'Content-Type': 'text/html',
            // Clear the oauth state cookie
            'Set-Cookie': 'oauth_state=; HttpOnly; Path=/; SameSite=Lax; Max-Age=0'
          },
        });

      } catch (error) {
        console.error('OAuth error:', error);
        return new Response('Authentication failed', { status: 500 });
      }
    }

    // Add GitHub users form
    if (url.pathname === '/add-users') {
      if (req.method === 'POST') {
        const formData = await req.formData();
        const usernames = formData.get('usernames')?.toString() || '';
        
        // Process each username
        const results = [];
        for (const username of usernames.split('\n').map(u => u.trim()).filter(Boolean)) {
          const result = await addGitHubUser(username);
          results.push(`${username}: ${result.message}`);
        }

        // Return results page
        return new Response(`
          <!DOCTYPE html>
          <html>
            <head>
              <title>Add Users Results</title>
              <style>
                body { font-family: system-ui; max-width: 800px; margin: 2rem auto; padding: 0 1rem; }
                pre { background: #f5f5f5; padding: 1rem; border-radius: 4px; }
              </style>
            </head>
            <body>
              <h1>Results</h1>
              <pre>${results.join('\n')}</pre>
              <p><a href="/add-users">← Back to form</a></p>
            </body>
          </html>
        `, {
          headers: { 'Content-Type': 'text/html' }
        });
      }

      // Show form
      return new Response(`
        <!DOCTYPE html>
        <html>
          <head>
            <title>Add GitHub Users</title>
            <style>
              body { font-family: system-ui; max-width: 800px; margin: 2rem auto; padding: 0 1rem; }
              textarea { width: 100%; height: 200px; margin: 1rem 0; }
              button { background: #2ea44f; color: white; border: none; padding: 0.5rem 1rem; border-radius: 4px; cursor: pointer; }
              button:hover { background: #2c974b; }
            </style>
          </head>
          <body>
            <h1>Add GitHub Users to Track</h1>
            <p>Enter one GitHub username per line:</p>
            <form method="POST">
              <textarea name="usernames" placeholder="zachlatta
maxwofford
..."></textarea>
              <br>
              <button type="submit">Add Users</button>
            </form>
          </body>
        </html>
      `, {
        headers: { 'Content-Type': 'text/html' }
      });
    }

    // Start scraping
    if (url.pathname === '/start-scrape') {
      // Start scraping in the background
      scraper.scrapeAllUsers().catch(error => {
        console.error('Scraping error:', error);
      });

      // Return immediate response
      return new Response(`
        <!DOCTYPE html>
        <html>
          <head>
            <title>Scraping Started</title>
            <style>
              body { font-family: system-ui; max-width: 800px; margin: 2rem auto; padding: 0 1rem; }
            </style>
          </head>
          <body>
            <h1>Scraping Started</h1>
            <p>The scraping process has been started in the background. Check the server logs for progress.</p>
            <p><a href="/">← Back to home</a></p>
          </body>
        </html>
      `, {
        headers: { 'Content-Type': 'text/html' }
      });
    }

    // Home page
    if (url.pathname === '/') {
      return new Response(`
        <!DOCTYPE html>
        <html>
          <head>
            <title>GitHub Data Collection</title>
            <style>
              body { font-family: system-ui; max-width: 800px; margin: 2rem auto; padding: 0 1rem; }
              .nav { margin: 2rem 0; }
              .nav a { margin-right: 1rem; }
              .button {
                display: inline-block;
                padding: 0.5rem 1rem;
                background: #2ea44f;
                color: white;
                text-decoration: none;
                border-radius: 4px;
              }
              .button:hover { background: #2c974b; }
              .button.secondary {
                background: #6e7781;
              }
              .button.secondary:hover {
                background: #5e666e;
              }
            </style>
          </head>
          <body>
            <h1>GitHub Data Collection</h1>
            <div class="nav">
              <a href="/auth/github" class="button">Donate Token</a>
              <a href="/add-users" class="button">Add Users to Track</a>
              <a href="/start-scrape" class="button secondary">Start Scraping All Users</a>
            </div>
          </body>
        </html>
      `, {
        headers: { 'Content-Type': 'text/html' },
      });
    }

    return new Response('Not Found', { status: 404 });
  },
});

console.log(`Server running at http://localhost:${port}`); 