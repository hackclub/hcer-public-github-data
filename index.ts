import { Octokit } from "@octokit/rest";
import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();
const octokit = new Octokit({
  auth: process.env.GITHUB_TOKEN,
});

// Rate limit handling
const checkRateLimit = async () => {
  const { data } = await octokit.rateLimit.get();
  console.log(`Rate limit status - Remaining: ${data.rate.remaining}/${data.rate.limit}, Reset: ${new Date(data.rate.reset * 1000).toISOString()}`);
  if (data.rate.remaining < 100) {
    const resetTime = new Date(data.rate.reset * 1000);
    const waitTime = resetTime.getTime() - Date.now();
    console.log(`Rate limit low (${data.rate.remaining} remaining). Waiting ${Math.ceil(waitTime / 1000)} seconds until ${resetTime.toISOString()}...`);
    await new Promise(resolve => setTimeout(resolve, waitTime));
  }
};

// Store organization data
async function storeOrg(org: any) {
  console.log(`Storing/updating organization: ${org.login} (ID: ${org.id})`);
  await prisma.organization.upsert({
    where: { orgId: org.id },
    update: { rawData: org },
    create: { orgId: org.id, rawData: org },
  });
}

// Store repository data
async function storeRepo(repo: any) {
  console.log(`Storing/updating repository: ${repo.full_name} (ID: ${repo.id})`);
  await prisma.repository.upsert({
    where: { repoId: repo.id },
    update: { rawData: repo },
    create: { repoId: repo.id, rawData: repo },
  });
}

// Store commit data
async function storeCommit(commit: any) {
  const authorName = commit.author?.login || commit.commit?.author?.name || 'unknown';
  const date = commit.commit?.author?.date;
  console.log(`Storing/updating commit: ${commit.sha.substring(0, 7)} by ${authorName} from ${date}`);
  await prisma.commit.upsert({
    where: { sha: commit.sha },
    update: { rawData: commit },
    create: { sha: commit.sha, rawData: commit },
  });
}

// Get existing commit range for a repository
async function getCommitRange(repoFullName: string) {
  console.log(`Querying commit date range for repository: ${repoFullName}`);
  // Get oldest commit
  const oldestCommit = await prisma.$queryRaw`
    SELECT ("rawData"->'commit'->'author'->>'date') as date
    FROM "Commit"
    WHERE ("rawData"->'repository'->>'full_name') = ${repoFullName}
    ORDER BY ("rawData"->'commit'->'author'->>'date')::timestamp ASC
    LIMIT 1
  `;

  // Get newest commit
  const newestCommit = await prisma.$queryRaw`
    SELECT ("rawData"->'commit'->'author'->>'date') as date
    FROM "Commit"
    WHERE ("rawData"->'repository'->>'full_name') = ${repoFullName}
    ORDER BY ("rawData"->'commit'->'author'->>'date')::timestamp DESC
    LIMIT 1
  `;

  const result = {
    oldest: oldestCommit[0]?.date || null,
    newest: newestCommit[0]?.date || null
  };
  console.log(`Found commit range for ${repoFullName}: ${result.oldest || 'none'} to ${result.newest || 'none'}`);
  return result;
}

// Get all organizations for a user with pagination
async function getUserOrgs(username: string) {
  console.log(`\nFetching organizations for user: ${username}`);
  let page = 1;
  const per_page = 100;
  const allOrgs = [];

  while (true) {
    await checkRateLimit();
    console.log(`Fetching organizations page ${page}...`);
    const { data: orgs } = await octokit.orgs.listForUser({
      username,
      per_page,
      page,
    });

    if (orgs.length === 0) {
      console.log('No more organizations found.');
      break;
    }

    console.log(`Found ${orgs.length} organizations on page ${page}`);
    for (const org of orgs) {
      await storeOrg(org);
      allOrgs.push(org);
    }

    if (orgs.length < per_page) {
      console.log('Reached last page of organizations.');
      break;
    }
    page++;
  }

  console.log(`Total organizations found for ${username}: ${allOrgs.length}`);
  return allOrgs;
}

// Get commits for a repository within a specific date range using search API
async function getCommitsInRange(owner: string, repo: string, username: string, since?: string, until?: string) {
  let page = 1;
  const per_page = 100;
  let totalCommits = 0;

  // Construct the search query
  let searchQuery = `repo:${owner}/${repo} author:${username}`;
  if (since) {
    searchQuery += ` author-date:>=${since}`;
  }
  if (until) {
    searchQuery += ` author-date:<=${until}`;
  }

  console.log(`\nSearching commits with query: ${searchQuery}`);

  while (true) {
    try {
      await checkRateLimit();
      console.log(`Fetching commits page ${page}...`);
      const { data } = await octokit.rest.search.commits({
        q: searchQuery,
        per_page,
        page,
        sort: 'author-date',
        order: since ? 'asc' : 'desc'
      });
      
      if (data.items.length === 0) {
        console.log('No more commits found.');
        break;
      }
      
      console.log(`Found ${data.items.length} commits on page ${page}. Total results: ${data.total_count}`);
      
      for (const commit of data.items) {
        await checkRateLimit();
        console.log(`Fetching full commit details for ${commit.sha.substring(0, 7)}...`);
        const { data: fullCommit } = await octokit.repos.getCommit({
          owner,
          repo,
          ref: commit.sha
        });
        
        await storeCommit(fullCommit);
        totalCommits++;
      }
      
      if (data.items.length < per_page) {
        console.log('Reached last page of commits.');
        break;
      }
      page++;
    } catch (error: any) {
      if (error.status === 409) {
        console.log(`Repository ${owner}/${repo} is empty or inaccessible`);
        break;
      }
      if (error.status === 422) {
        console.log(`Search query invalid or no results for ${owner}/${repo}`);
        break;
      }
      console.error(`Error fetching commits: ${error.message}`);
      throw error;
    }
  }

  console.log(`Total commits processed: ${totalCommits}`);
}

// Get all commits for a repository with intelligent pagination
async function getAllCommits(owner: string, repo: string, username: string) {
  try {
    const repoFullName = `${owner}/${repo}`;
    console.log(`\n=== Processing commits for ${username} in ${repoFullName} ===`);
    
    // Get existing commit range
    const { oldest, newest } = await getCommitRange(repoFullName);
    
    if (!oldest && !newest) {
      console.log(`No existing commits found for ${username} in ${repoFullName}, fetching all...`);
      await getCommitsInRange(owner, repo, username);
    } else {
      // Fetch newer commits first (if any)
      if (newest) {
        console.log(`Fetching commits newer than ${newest} for ${username} in ${repoFullName}...`);
        await getCommitsInRange(owner, repo, username, newest);
      }
      
      // Then fetch older commits (if any)
      if (oldest) {
        console.log(`Fetching commits older than ${oldest} for ${username} in ${repoFullName}...`);
        await getCommitsInRange(owner, repo, username, undefined, oldest);
      }
    }
    console.log(`=== Finished processing ${repoFullName} ===\n`);
  } catch (error: any) {
    if (error.status === 409) {
      console.log(`Repository ${owner}/${repo} is empty or inaccessible`);
      return;
    }
    console.error(`Error processing repository ${owner}/${repo}: ${error.message}`);
    throw error;
  }
}

// Get all repositories for a user or organization with pagination
async function getRepos(owner: string, username: string, isOrg = false) {
  console.log(`\nFetching repositories for ${isOrg ? 'organization' : 'user'}: ${owner}`);
  let page = 1;
  const per_page = 100;
  let totalRepos = 0;

  while (true) {
    await checkRateLimit();
    console.log(`Fetching repositories page ${page}...`);
    const { data: repos } = isOrg 
      ? await octokit.repos.listForOrg({
          org: owner,
          per_page,
          page,
          type: 'public'
        })
      : await octokit.repos.listForUser({
          username: owner,
          per_page,
          page,
          type: 'owner'
        });

    if (repos.length === 0) {
      console.log('No more repositories found.');
      break;
    }

    console.log(`Found ${repos.length} repositories on page ${page}`);
    for (const repo of repos) {
      await storeRepo(repo);
      await getAllCommits(repo.owner.login, repo.name, username);
      totalRepos++;
    }

    if (repos.length < per_page) {
      console.log('Reached last page of repositories.');
      break;
    }
    page++;
  }

  console.log(`Total repositories processed for ${owner}: ${totalRepos}`);
}

async function main() {
  console.log('Starting GitHub data collection...');
  const usernames = process.argv.slice(2);
  if (usernames.length === 0) {
    console.error("Please provide GitHub usernames as arguments");
    process.exit(1);
  }

  if (!process.env.GITHUB_TOKEN) {
    console.error("Please set GITHUB_TOKEN environment variable");
    process.exit(1);
  }

  try {
    for (const username of usernames) {
      console.log(`\n=== Processing user: ${username} ===`);
      const orgs = await getUserOrgs(username);
      await getRepos(username, username, false);
      
      for (const org of orgs) {
        console.log(`\n=== Processing organization: ${org.login} ===`);
        await getRepos(org.login, username, true);
      }
      console.log(`\n=== Finished processing user: ${username} ===`);
    }
    console.log('\nData collection completed successfully!');
  } catch (error) {
    console.error('Fatal error:', error);
    process.exit(1);
  } finally {
    await prisma.$disconnect();
  }
}

main();