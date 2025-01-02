import { PrismaClient, User, APIRequest } from '@prisma/client';
import { Octokit } from 'octokit';

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
  private prisma: PrismaClient;

  constructor() {
    this.prisma = new PrismaClient();
  }

  private async findAvailableToken(): Promise<User | null> {
    const now = new Date();

    // Find a user token that:
    // 1. Has rate limit remaining
    // 2. Rate limit reset time has passed if limit was previously exhausted
    // 3. Token is not expired
    return await prisma.user.findFirst({
      where: {
        OR: [
          { rateLimitRemaining: { gt: 0 } },
          { rateLimitReset: { lt: now } }
        ],
        AND: {
          tokenExpiry: { gt: now }
        }
      },
      orderBy: [
        { rateLimitRemaining: 'desc' },
        { lastUsed: 'asc' }
      ]
    });
  }

  private async refreshToken(user: User): Promise<User> {
    if (!user.refreshToken) {
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
        refresh_token: user.refreshToken,
        grant_type: 'refresh_token',
      }),
    });

    if (!response.ok) {
      throw new GitHubAPIError('Failed to refresh token', 'REFRESH_FAILED');
    }

    const data = await response.json();
    
    return await prisma.user.update({
      where: { id: user.id },
      data: {
        accessToken: data.access_token,
        refreshToken: data.refresh_token,
        tokenExpiry: new Date(Date.now() + (data.expires_in * 1000)),
      },
    });
  }

  private async updateRateLimits(user: User, headers: Headers): Promise<User> {
    const remaining = parseInt(headers.get('x-ratelimit-remaining') || '0');
    const reset = new Date(parseInt(headers.get('x-ratelimit-reset') || '0') * 1000);
    const limit = parseInt(headers.get('x-ratelimit-limit') || '0');

    return await prisma.user.update({
      where: { id: user.id },
      data: {
        rateLimitRemaining: remaining,
        rateLimitReset: reset,
        lastUsed: new Date(),
      },
    });
  }

  private async logRequest(
    user: User,
    request: RequestOptions,
    response: Response,
    responseBody: any
  ): Promise<APIRequest> {
    const headers: Record<string, string> = {};
    response.headers.forEach((value, key) => {
      headers[key] = value;
    });

    return await prisma.aPIRequest.create({
      data: {
        userId: user.id,
        requestUrl: request.url,
        requestParams: request.params || {},
        responseHeaders: headers,
        responseBody,
        statusCode: response.status,
        rateLimit: parseInt(response.headers.get('x-ratelimit-limit') || '0'),
        rateLimitRemaining: parseInt(response.headers.get('x-ratelimit-remaining') || '0'),
        rateLimitReset: new Date(parseInt(response.headers.get('x-ratelimit-reset') || '0') * 1000),
      },
    });
  }

  async request<T = any>(options: RequestOptions): Promise<{ data: T; requestId: string }> {
    let user = await this.findAvailableToken();
    if (!user) {
      throw new NoAvailableTokenError();
    }

    // If token is expired, try to refresh it
    if (user.tokenExpiry <= new Date()) {
      try {
        user = await this.refreshToken(user);
      } catch (error) {
        // If refresh fails, try to find another token
        user = await this.findAvailableToken();
        if (!user) {
          throw new NoAvailableTokenError();
        }
      }
    }

    const octokit = new Octokit({ auth: user.accessToken });
    
    try {
      const response = await octokit.request({
        method: options.method || 'GET',
        url: options.url,
        ...options.params,
      });

      // Update rate limits
      await this.updateRateLimits(user, new Headers(response.headers as any));

      // Log the request
      const apiRequest = await this.logRequest(user, options, {
        ok: true,
        status: response.status,
        headers: new Headers(response.headers as any),
      } as Response, response.data);

      return {
        data: response.data,
        requestId: apiRequest.id,
      };
    } catch (error: any) {
      if (error.status === 403 && error.response?.headers?.['x-ratelimit-remaining'] === '0') {
        // Update rate limits even for failed requests
        await this.updateRateLimits(user, new Headers(error.response.headers));
        throw new RateLimitError('Rate limit exceeded');
      }
      throw error;
    }
  }
} 