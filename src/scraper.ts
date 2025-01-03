import { PrismaClient, GitHubUser, Organization, Repository } from '@prisma/client';
import { GitHubAPI } from './github';

// Share a single PrismaClient instance across all scrapers
const prisma = new PrismaClient();

export class GitHubScraper {
  private github: GitHubAPI;
  private workerId?: number;

  constructor(workerId?: number) {
    this.github = new GitHubAPI();
    this.workerId = workerId;
  }

  private log(message: string, data?: any) {
    const timestamp = new Date().toISOString();
    const workerPrefix = this.workerId !== undefined ? `[Worker ${this.workerId}] ` : '';
    console.log(`[${timestamp}] ${workerPrefix}${message}`);
    if (data) {
      console.log(JSON.stringify(data, null, 2));
    }
  }

  private async fetchAndStoreOrganization(orgLogin: string): Promise<Organization> {
    this.log(`Checking if organization ${orgLogin} exists`);
    
    // Check if org exists
    const existingOrg = await prisma.organization.findUnique({
      where: { login: orgLogin }
    });

    if (existingOrg) {
      this.log(`Organization ${orgLogin} already exists`, { id: existingOrg.id });
      return existingOrg;
    }

    this.log(`Fetching organization data for ${orgLogin}`);
    // Fetch org data
    const { data: orgData, requestId } = await this.github.request({
      url: `/orgs/${orgLogin}`
    });

    this.log(`Creating organization ${orgLogin}`, { id: orgData.id });
    // Store org
    return await prisma.organization.create({
      data: {
        id: orgData.id,
        login: orgData.login,
        name: orgData.name || null,
        description: orgData.description || null,
        avatarUrl: orgData.avatar_url || null,
        fetchedFromRequest: {
          connect: { id: requestId }
        }
      }
    });
  }

  private async fetchAndStoreRepository(owner: string, repo: string, ownerType: 'user' | 'org'): Promise<Repository> {
    const fullName = `${owner}/${repo}`;
    this.log(`Checking if repository ${fullName} exists`);

    // Check if repo exists
    const existingRepo = await prisma.repository.findUnique({
      where: { fullName }
    });

    if (existingRepo) {
      this.log(`Repository ${fullName} already exists`, { id: existingRepo.id });
      return existingRepo;
    }

    this.log(`Fetching repository data for ${fullName}`);
    // Fetch repo data
    const { data: repoData, requestId } = await this.github.request({
      url: `/repos/${fullName}`
    });

    // Get owner ID based on type
    let ownerId: number | null = null;
    let orgId: number | null = null;

    if (ownerType === 'user') {
      this.log(`Looking up user owner ${owner}`);
      const ownerUser = await prisma.gitHubUser.findUnique({
        where: { login: owner }
      });
      ownerId = ownerUser?.id || null;
      this.log(`Found user owner`, { userId: ownerId });
    } else {
      this.log(`Looking up organization owner ${owner}`);
      const ownerOrg = await prisma.organization.findUnique({
        where: { login: owner }
      });
      orgId = ownerOrg?.id || null;
      this.log(`Found organization owner`, { orgId });
    }

    this.log(`Creating repository ${fullName}`, {
      id: repoData.id,
      ownerId,
      orgId
    });

    // Store repo
    return await prisma.repository.create({
      data: {
        id: repoData.id,
        name: repoData.name,
        fullName: repoData.full_name,
        description: repoData.description || null,
        isPrivate: repoData.private,
        isFork: repoData.fork,
        fetchedFromRequest: {
          connect: { id: requestId }
        },
        ...(ownerId ? {
          owner: {
            connect: { id: ownerId }
          }
        } : {}),
        ...(orgId ? {
          organization: {
            connect: { id: orgId }
          }
        } : {})
      }
    });
  }

  private async fetchAndStoreCommits(repo: Repository, user: GitHubUser) {
    // First, get the date range of existing commits for this user and repo
    const existingCommits = await prisma.commit.findMany({
      where: {
        repoId: repo.id,
        OR: [
          { authorId: user.id },
          { committerId: user.id }
        ]
      },
      orderBy: [
        { committedDate: 'desc' }
      ],
      select: {
        committedDate: true
      }
    });

    let newestCommitDate: Date | null = null;
    let oldestCommitDate: Date | null = null;

    if (existingCommits.length > 0) {
      newestCommitDate = existingCommits[0].committedDate;
      oldestCommitDate = existingCommits[existingCommits.length - 1].committedDate;
      this.log(`Found existing commits for ${repo.fullName}`, {
        count: existingCommits.length,
        newestCommit: newestCommitDate.toISOString(),
        oldestCommit: oldestCommitDate.toISOString()
      });
    }

    // Function to fetch commits for a specific date range
    const fetchCommitsInRange = async (since?: string, until?: string) => {
      let page = 1;
      const perPage = 100;
      let totalCommits = 0;

      while (true) {
        this.log(`Fetching commits page ${page} for ${repo.fullName}`, {
          since,
          until
        });

        // Build the search query
        let searchQuery = `repo:${repo.fullName} author:${user.login} committer:${user.login}`;
        if (since) searchQuery += ` committer-date:>=${since}`;
        if (until) searchQuery += ` committer-date:<=${until}`;

        // Use search API to find commits by the user
        const { data: searchData, requestId } = await this.github.request({
          url: '/search/commits',
          params: {
            q: searchQuery,
            sort: 'committer-date',
            order: 'desc',
            per_page: perPage,
            page
          }
        });

        if (searchData.items.length === 0) {
          this.log(`No more commits found for ${repo.fullName} in range`, { since, until });
          break;
        }

        this.log(`Found ${searchData.items.length} commits on page ${page}`);

        // Store each commit
        for (const commitData of searchData.items) {
          try {
            const commitCreateData = {
              id: commitData.sha,
              message: commitData.commit.message,
              authoredDate: new Date(commitData.commit.author.date),
              committedDate: new Date(commitData.commit.committer.date),
              fetchedFromRequest: {
                connect: { id: requestId }
              },
              repository: { 
                connect: { id: repo.id }
              },
              ...(commitData.author?.id ? {
                author: { 
                  connect: { id: commitData.author.id }
                }
              } : {}),
              ...(commitData.committer?.id ? {
                committer: { 
                  connect: { id: commitData.committer.id }
                }
              } : {})
            };

            this.log(`Processing commit ${commitData.sha}`, {
              message: commitData.commit.message.split('\n')[0], // First line only
              authorId: commitData.author?.id,
              committerId: commitData.committer?.id,
              date: commitData.commit.committer.date
            });

            // Try to create the commit first
            try {
              await prisma.commit.create({
                data: commitCreateData
              });
              this.log(`Created new commit ${commitData.sha}`);
              totalCommits++;
            } catch (error: any) {
              // If commit exists, update its relationships
              if (error.code === 'P2002') {
                this.log(`Updating existing commit ${commitData.sha}`);
                await prisma.commit.update({
                  where: { id: commitData.sha },
                  data: {
                    fetchedFromRequest: {
                      connect: { id: requestId }
                    },
                    repository: { 
                      connect: { id: repo.id }
                    },
                    ...(commitData.author?.id ? {
                      author: { 
                        connect: { id: commitData.author.id }
                      }
                    } : {}),
                    ...(commitData.committer?.id ? {
                      committer: { 
                        connect: { id: commitData.committer.id }
                      }
                    } : {})
                  }
                });
                totalCommits++;
              } else {
                throw error;
              }
            }
          } catch (error) {
            this.log(`Error processing commit ${commitData.sha}`, {
              error: error instanceof Error ? error.message : 'Unknown error'
            });
          }
        }

        if (searchData.items.length < perPage) {
          this.log(`Reached last page of commits for ${repo.fullName} in range`, { since, until });
          break;
        }

        page++;
      }

      return totalCommits;
    };

    let totalNewCommits = 0;

    // Fetch newer commits first (if we have existing commits)
    if (newestCommitDate) {
      const newCommits = await fetchCommitsInRange(
        new Date(newestCommitDate.getTime() + 1000).toISOString().split('T')[0]
      );
      totalNewCommits += newCommits;
      this.log(`Fetched ${newCommits} new commits after ${newestCommitDate.toISOString()}`);
    }

    // Fetch older commits (if we have existing commits)
    if (oldestCommitDate) {
      const oldCommits = await fetchCommitsInRange(
        undefined,
        new Date(oldestCommitDate.getTime() - 1000).toISOString().split('T')[0]
      );
      totalNewCommits += oldCommits;
      this.log(`Fetched ${oldCommits} old commits before ${oldestCommitDate.toISOString()}`);
    }

    // If we don't have any existing commits, fetch all commits
    if (!newestCommitDate && !oldestCommitDate) {
      const allCommits = await fetchCommitsInRange();
      totalNewCommits = allCommits;
      this.log(`Fetched ${allCommits} commits for new repository`);
    }

    this.log(`Finished processing commits for ${repo.fullName}`, {
      totalNewCommits,
      existingCommits: existingCommits.length
    });
  }

  async scrapeUser(user: GitHubUser) {
    this.log(`Starting data collection for user ${user.login}`, {
      userId: user.id,
      name: user.name
    });

    // Fetch user's organizations
    this.log(`Fetching organizations for ${user.login}`);
    const { data: orgs, requestId: orgsRequestId } = await this.github.request({
      url: `/users/${user.login}/orgs`
    });

    this.log(`Found ${orgs.length} organizations for ${user.login}`);

    // Store each organization
    for (const org of orgs) {
      try {
        await this.fetchAndStoreOrganization(org.login);
        this.log(`Connecting user ${user.login} to organization ${org.login}`);
        // Update user-org relationship
        await prisma.gitHubUser.update({
          where: { id: user.id },
          data: {
            organizations: {
              connect: { login: org.login }
            }
          }
        });
      } catch (error) {
        this.log(`Error processing organization ${org.login}`, {
          error: error instanceof Error ? error.message : 'Unknown error'
        });
      }
    }

    // Fetch user's repositories
    this.log(`Fetching repositories for ${user.login}`);
    const { data: repos } = await this.github.request({
      url: `/users/${user.login}/repos`,
      params: {
        type: 'all',
        sort: 'updated',
        per_page: 100
      }
    });

    this.log(`Found ${repos.length} repositories for ${user.login}`);

    // Store each repository and its commits
    for (const repo of repos) {
      try {
        const storedRepo = await this.fetchAndStoreRepository(
          repo.owner.login,
          repo.name,
          repo.owner.type.toLowerCase() as 'user' | 'org'
        );
        await this.fetchAndStoreCommits(storedRepo, user);
      } catch (error) {
        this.log(`Error processing repository ${repo.full_name}`, {
          error: error instanceof Error ? error.message : 'Unknown error'
        });
      }
    }

    // Update user's last fetched time
    this.log(`Updating last fetched time for ${user.login}`);
    await prisma.gitHubUser.update({
      where: { id: user.id },
      data: { lastFetched: new Date() }
    });

    this.log(`Completed data collection for ${user.login}`);
  }

  private async processUserBatch(users: GitHubUser[], workerId: number) {
    this.workerId = workerId;
    this.log(`Starting batch processing of ${users.length} users`);
    
    for (const user of users) {
      try {
        await this.scrapeUser(user);
      } catch (error) {
        this.log(`Error scraping user ${user.login}`, {
          error: error instanceof Error ? error.message : 'Unknown error'
        });
      }
    }

    this.log(`Completed batch processing of ${users.length} users`);
  }

  async scrapeAllUsers(numWorkers: number = 10) {
    if (numWorkers < 1) {
      throw new Error('Number of workers must be at least 1');
    }

    this.log('Starting full data collection');
    const users = await prisma.gitHubUser.findMany({
      orderBy: {
        lastFetched: 'asc'
      }
    });
    this.log(`Found ${users.length} users to process`);

    // Split users into chunks for parallel processing
    const chunkSize = Math.ceil(users.length / numWorkers);
    const chunks = Array.from({ length: numWorkers }, (_, i) => 
      users.slice(i * chunkSize, (i + 1) * chunkSize)
    );

    // Create separate scraper instances for each worker
    const workerPromises = chunks.map((chunk, index) => {
      const workerScraper = new GitHubScraper(index);
      return workerScraper.processUserBatch(chunk, index);
    });

    try {
      await Promise.all(workerPromises);
      this.log('Completed full data collection');
    } catch (error) {
      this.log('Error during parallel processing', {
        error: error instanceof Error ? error.message : 'Unknown error'
      });
      throw error;
    }
  }
} 