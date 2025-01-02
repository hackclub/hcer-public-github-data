import { PrismaClient } from '@prisma/client';
import { Octokit } from 'octokit';

const prisma = new PrismaClient();
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

    // Login page
    if (url.pathname === '/') {
      return new Response(`
        <!DOCTYPE html>
        <html>
          <head>
            <title>GitHub Token Donation</title>
          </head>
          <body>
            <h1>Donate your GitHub Token</h1>
            <p>Click below to login with GitHub and donate your access token.</p>
            <a href="/auth/github">Login with GitHub</a>
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