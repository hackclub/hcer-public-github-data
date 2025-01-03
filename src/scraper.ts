import { PrismaClient, GitHubUser, Organization, Repository, ScrapeJob, UserRepositoryScrapeJob } from '@prisma/client';
import { GitHubAPI } from './github';

// Share a single PrismaClient instance across all scrapers
const prisma = new PrismaClient();

export class GitHubScraper {
  private github: GitHubAPI;
  private workerId?: number;
  private currentScrapeJob?: ScrapeJob;
  private currentScrapeJobId?: string;
  private heartbeatInterval?: NodeJS.Timeout;
  private readonly HEARTBEAT_INTERVAL = 5000; // 5 seconds

  constructor(workerId?: number, scrapeJobId?: string) {
    this.github = new GitHubAPI();
    this.workerId = workerId;
    this.currentScrapeJobId = scrapeJobId;
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

  private async updateHeartbeat() {
    if (!this.currentScrapeJobId) return;

    try {
      await prisma.scrapeJob.update({
        where: { id: this.currentScrapeJobId },
        data: { lastHeartbeatAt: new Date() }
      });
    } catch (error) {
      this.log('Failed to update heartbeat', {
        error: error instanceof Error ? error.message : 'Unknown error'
      });
    }
  }

  private startHeartbeat() {
    if (this.heartbeatInterval) {
      clearInterval(this.heartbeatInterval);
    }

    this.heartbeatInterval = setInterval(() => {
      this.updateHeartbeat();
    }, this.HEARTBEAT_INTERVAL);
  }

  private stopHeartbeat() {
    if (this.heartbeatInterval) {
      clearInterval(this.heartbeatInterval);
      this.heartbeatInterval = undefined;
    }
  }

  private async startScrapeJob(type: string, metadata?: any): Promise<ScrapeJob> {
    this.log(`Starting new scrape job of type ${type}`);
    
    const job = await prisma.scrapeJob.create({
      data: {
        type,
        metadata: metadata || {},
        status: 'RUNNING',
        lastHeartbeatAt: new Date()
      }
    });

    this.currentScrapeJob = job;
    this.currentScrapeJobId = job.id;
    this.startHeartbeat();
    return job;
  }

  private async completeScrapeJob(error?: string) {
    if (!this.currentScrapeJob) return;

    this.stopHeartbeat();

    if (error) {
      this.log(`Marking scrape job as errored: ${error}`);
      await prisma.scrapeJob.update({
        where: { id: this.currentScrapeJob.id },
        data: {
          status: 'ERRORED',
          erroredAt: new Date(),
          error
        }
      });
    } else {
      this.log('Marking scrape job as completed');
      await prisma.scrapeJob.update({
        where: { id: this.currentScrapeJob.id },
        data: {
          status: 'COMPLETED',
          completedAt: new Date()
        }
      });
    }
  }

  private async getCurrentScrapeJob(): Promise<ScrapeJob> {
    if (!this.currentScrapeJobId) {
      throw new Error('No active scrape job');
    }

    if (!this.currentScrapeJob) {
      this.currentScrapeJob = await prisma.scrapeJob.findUnique({
        where: { id: this.currentScrapeJobId }
      });
      
      if (!this.currentScrapeJob) {
        throw new Error(`Could not find scrape job with ID ${this.currentScrapeJobId}`);
      }

      // Start heartbeat if we're attaching to an existing job
      this.startHeartbeat();
    }

    return this.currentScrapeJob;
  }

  private async startUserRepoScrape(user: GitHubUser, repo: Repository): Promise<UserRepositoryScrapeJob> {
    const scrapeJob = await this.getCurrentScrapeJob();

    return await prisma.userRepositoryScrapeJob.create({
      data: {
        scrapeJob: { connect: { id: scrapeJob.id } },
        user: { connect: { id: user.id } },
        repository: { connect: { id: repo.id } },
        status: 'RUNNING'
      }
    });
  }

  private async completeUserRepoScrape(job: UserRepositoryScrapeJob, newCommits: number, error?: string) {
    if (error) {
      this.log(`Marking user repo scrape as errored: ${error}`);
      await prisma.userRepositoryScrapeJob.update({
        where: { id: job.id },
        data: {
          status: 'ERRORED',
          erroredAt: new Date(),
          error,
          newCommits
        }
      });
    } else {
      this.log('Marking user repo scrape as completed');
      await prisma.userRepositoryScrapeJob.update({
        where: { id: job.id },
        data: {
          status: 'COMPLETED',
          completedAt: new Date(),
          newCommits
        }
      });
    }
  }

  private async shouldSkipRepoForUser(user: GitHubUser, repo: Repository): Promise<boolean> {
    // Find the last successful scrape for this user/repo combination
    const lastSuccessfulScrape = await prisma.userRepositoryScrapeJob.findFirst({
      where: {
        userId: user.id,
        repoId: repo.id,
        status: 'COMPLETED'
      },
      orderBy: {
        completedAt: 'desc'
      }
    });

    if (!lastSuccessfulScrape) {
      return false; // No successful scrape yet, don't skip
    }

    // If the repo hasn't been pushed to since our last scrape, we can skip it
    if (lastSuccessfulScrape.completedAt > repo.updatedAt) {
      this.log(`Skipping ${repo.fullName} for user ${user.login} - no new pushes since last scrape`);
      return true;
    }

    return false;
  }

  private async fetchAndStoreCommits(repo: Repository, user: GitHubUser, userRepoJob: UserRepositoryScrapeJob) {
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
        newestCommit: newestCommitDate?.toISOString(),
        oldestCommit: oldestCommitDate?.toISOString()
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

        // Get all commit SHAs from this batch
        const commitShas = searchData.items.map(item => item.sha);
        
        // Check which commits already exist in the database
        const existingCommits = await prisma.commit.findMany({
          where: {
            id: { in: commitShas }
          },
          select: {
            id: true
          }
        });
        const existingCommitShas = new Set(existingCommits.map(c => c.id));

        // Prepare batch of new commits
        const newCommits = searchData.items
          .filter(commitData => !existingCommitShas.has(commitData.sha))
          .map(commitData => ({
            id: commitData.sha,
            message: commitData.commit.message,
            authoredDate: new Date(commitData.commit.author.date),
            committedDate: new Date(commitData.commit.committer.date),
            fetchedFromRequestId: requestId,
            repoId: repo.id,
            authorId: commitData.author?.id || null,
            committerId: commitData.committer?.id || null
          }));

        if (newCommits.length > 0) {
          try {
            await prisma.commit.createMany({
              data: newCommits,
              skipDuplicates: true // Extra safety measure
            });
            this.log(`Created ${newCommits.length} new commits in batch`);
            totalCommits += newCommits.length;
          } catch (error) {
            this.log(`Error processing commit batch`, {
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

    try {
      await this.completeUserRepoScrape(userRepoJob, totalNewCommits);
    } catch (error: any) {
      await this.completeUserRepoScrape(userRepoJob, totalNewCommits, error.message);
      throw error;
    }
  }

  async scrapeUser(user: GitHubUser) {
    try {
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
          sort: 'pushed',
          direction: 'desc',
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

          const shouldSkip = await this.shouldSkipRepoForUser(user, storedRepo);
          if (shouldSkip) {
            this.log(`Skipping ${storedRepo.fullName} for user ${user.login} - no new pushes since last scrape`);
            continue;
          }

          const userRepoJob = await this.startUserRepoScrape(user, storedRepo);
          await this.fetchAndStoreCommits(storedRepo, user, userRepoJob);
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
    } catch (error: any) {
      throw error;
    }
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
    try {
      const scrapeJob = await this.startScrapeJob('FULL_SYNC');
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
        const workerScraper = new GitHubScraper(index, scrapeJob.id);
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
      } finally {
        this.stopHeartbeat();
      }

      await this.completeScrapeJob();
    } catch (error: any) {
      await this.completeScrapeJob(error.message);
      throw error;
    }
  }
} 