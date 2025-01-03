import { PrismaClient, AccessToken, APIRequest } from '@prisma/client';
import { Octokit } from 'octokit';

// Use a single Prisma client instance
const prisma = new PrismaClient();

export class GitHubAPIError extends Error {
  constructor(message: string, public readonly code: string) {
    super(message);
    this.name = 'GitHubAPIError';
  }
}

export class RateLimitError extends GitHubAPIError {
  constructor(message: string) {
    super(message, 'RATE_LIMIT');
  }
}

export class NoAvailableTokenError extends GitHubAPIError {
  constructor() {
    super('No available access tokens', 'NO_TOKENS');
  }
}

interface RequestOptions {
  method?: string;
  url: string;
  params?: Record<string, any>;
}

export class GitHubAPI {
  private async getRateLimitScope(url: string): Promise<'core' | 'search' | 'graphql'> {
    if (url.startsWith('/search')) return 'search';
    if (url.startsWith('/graphql')) return 'graphql';
    return 'core';
  }

  private async findAvailableToken(): Promise<AccessToken | null> {
    const now = new Date();

    // Use a transaction to ensure we get a token and lock it atomically
    return await prisma.$transaction(async (tx) => {
      const token = await tx.accessToken.findFirst({
        where: {
          OR: [
            {
              OR: [
                { coreRateLimitRemaining: { gt: 0 } },
                { coreRateLimitReset: { lt: now } }
              ]
            },
            {
              OR: [
                { searchRateLimitRemaining: { gt: 0 } },
                { searchRateLimitReset: { lt: now } }
              ]
            },
            {
              OR: [
                { graphqlRateLimitRemaining: { gt: 0 } },
                { graphqlRateLimitReset: { lt: now } }
              ]
            }
          ],
          AND: {
            tokenExpiry: { gt: now },
            invalidAt: null
          }
        },
        orderBy: [
          { lastUsed: 'asc' }
        ]
      });

      if (!token) return null;

      // Lock the token by updating lastUsed
      return await tx.accessToken.update({
        where: { id: token.id },
        data: { lastUsed: now }
      });
    });
  }

  private async markTokenAsInvalid(token: AccessToken): Promise<void> {
    await prisma.accessToken.update({
      where: { id: token.id },
      data: {
        invalidAt: new Date(),
        coreRateLimitRemaining: 0,
        searchRateLimitRemaining: 0,
        graphqlRateLimitRemaining: 0
      }
    });
  }

  private async checkTokenValidity(token: AccessToken): Promise<boolean> {
    try {
      const octokit = new Octokit({ auth: token.accessToken });
      await octokit.request('GET /user');
      return true;
    } catch (error: any) {
      if (error.status === 401) {
        // Try to refresh the token before marking it as invalid
        try {
          if (token.refreshToken) {
            const refreshedToken = await this.refreshToken(token);
            // Test the refreshed token
            const octokit = new Octokit({ auth: refreshedToken.accessToken });
            await octokit.request('GET /user');
            return true;
          }
        } catch (refreshError) {
          console.log(`Failed to refresh token ${token.id} (${token.username}):`, refreshError);
        }
        
        console.log(`Token ${token.id} (${token.username}) has been revoked`);
        await this.markTokenAsInvalid(token);
        return false;
      }
      // For other errors (like rate limits), consider the token still valid
      return true;
    }
  }

  private async refreshToken(token: AccessToken): Promise<AccessToken> {
    if (!token.refreshToken) {
      throw new GitHubAPIError('No refresh token available', 'NO_REFRESH_TOKEN');
    }

    const response = await fetch('https://github.com/login/oauth/access_token', {
      method: 'POST',
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        client_id: process.env.GITHUB_CLIENT_ID,
        client_secret: process.env.GITHUB_CLIENT_SECRET,
        refresh_token: token.refreshToken,
        grant_type: 'refresh_token',
      }),
    });

    if (!response.ok) {
      throw new GitHubAPIError('Failed to refresh token', 'REFRESH_FAILED');
    }

    const data = await response.json();
    
    return await prisma.accessToken.update({
      where: { id: token.id },
      data: {
        accessToken: data.access_token,
        refreshToken: data.refresh_token,
        tokenExpiry: new Date(Date.now() + (data.expires_in * 1000)),
      },
    });
  }

  private async updateRateLimits(token: AccessToken, headers: Headers, url: string): Promise<AccessToken> {
    const scope = await this.getRateLimitScope(url);
    
    // Get all rate limit info to ensure we have the correct scope
    const octokit = new Octokit({ auth: token.accessToken });
    const { data: rateLimits } = await octokit.request('GET /rate_limit');
    
    // Use the appropriate scope's rate limits
    const limits = rateLimits.resources[scope];
    
    if (!limits) {
      console.warn(`No rate limits found for scope ${scope}`);
      return token;
    }
    
    console.log(`Rate limits for token ${token.id} (${token.username}) [${scope}]:`, {
      remaining: limits.remaining,
      limit: limits.limit,
      reset: new Date(limits.reset * 1000).toISOString(),
      scope
    });

    // Update the appropriate rate limit fields based on scope
    const updateData: any = {
      lastUsed: new Date()
    };

    switch (scope) {
      case 'core':
        updateData.coreRateLimitRemaining = limits.remaining;
        updateData.coreRateLimitReset = new Date(limits.reset * 1000);
        break;
      case 'search':
        updateData.searchRateLimitRemaining = limits.remaining;
        updateData.searchRateLimitReset = new Date(limits.reset * 1000);
        break;
      case 'graphql':
        updateData.graphqlRateLimitRemaining = limits.remaining;
        updateData.graphqlRateLimitReset = new Date(limits.reset * 1000);
        break;
    }

    return await prisma.accessToken.update({
      where: { id: token.id },
      data: updateData
    });
  }

  async request<T = any>(options: RequestOptions): Promise<{ data: T; requestId: string }> {
    let token = await this.findAvailableToken();
    if (!token) {
      throw new NoAvailableTokenError();
    }

    // If token is expired, try to refresh it
    if (token.tokenExpiry <= new Date()) {
      try {
        token = await this.refreshToken(token);
      } catch (error) {
        // If refresh fails, try to find another token
        token = await this.findAvailableToken();
        if (!token) {
          throw new NoAvailableTokenError();
        }
      }
    }

    const octokit = new Octokit({ auth: token.accessToken });
    
    try {
      const response = await octokit.request({
        method: options.method || 'GET',
        url: options.url,
        ...options.params,
      });

      // Update rate limits with the correct scope
      await this.updateRateLimits(token, new Headers(response.headers as any), options.url);

      // Log the request
      const apiRequest = await prisma.aPIRequest.create({
        data: {
          accessTokenId: token.id,
          requestUrl: options.url,
          requestParams: options.params || {},
          responseHeaders: Object.fromEntries(Object.entries(response.headers || {})),
          responseBody: response.data,
          statusCode: response.status,
          rateLimit: parseInt(response.headers['x-ratelimit-limit'] || '0'),
          rateLimitRemaining: parseInt(response.headers['x-ratelimit-remaining'] || '0'),
          rateLimitReset: new Date(parseInt(response.headers['x-ratelimit-reset'] || '0') * 1000),
        },
      });

      return {
        data: response.data,
        requestId: apiRequest.id,
      };
    } catch (error: any) {
      // Log the failed request
      const apiRequest = await prisma.aPIRequest.create({
        data: {
          accessTokenId: token.id,
          requestUrl: options.url,
          requestParams: options.params || {},
          responseHeaders: Object.fromEntries(Object.entries(error.response?.headers || {})),
          responseBody: error.response?.data || { error: error.message },
          statusCode: error.status || 500,
          rateLimit: error.response?.headers?.['x-ratelimit-limit'] 
            ? parseInt(error.response.headers['x-ratelimit-limit'])
            : null,
          rateLimitRemaining: error.response?.headers?.['x-ratelimit-remaining']
            ? parseInt(error.response.headers['x-ratelimit-remaining'])
            : null,
          rateLimitReset: error.response?.headers?.['x-ratelimit-reset']
            ? new Date(parseInt(error.response.headers['x-ratelimit-reset']) * 1000)
            : null,
        },
      });

      if (error.status === 401) {
        // Check if token has been revoked
        const isValid = await this.checkTokenValidity(token);
        if (!isValid) {
          // Try the request again with a new token
          return this.request(options);
        }
      }

      if (error.status === 403 && error.response?.headers?.['x-ratelimit-remaining'] === '0') {
        // Update rate limits even for failed requests
        await this.updateRateLimits(token, new Headers(error.response.headers), options.url);
        throw new RateLimitError('Rate limit exceeded');
      }
      
      throw error;
    }
  }
} 