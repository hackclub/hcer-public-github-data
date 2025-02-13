// This script uses Bun to try and fetch potential college students from GitHub by searching
//
// We can use root level async / await
//
// We should make requests in batches of 32

import fs from 'fs';
import { createObjectCsvWriter } from 'csv-writer';

const API_KEY = process.env.API_KEY;
if (!API_KEY) {
  console.error("Missing API_KEY in environment");
  process.exit(1);
}

// Prepare our CSV writer in append mode, but write headers if the file doesn't exist
const csvFilePath = 'output/source_undergrad_students.csv';
const fileExists = fs.existsSync(csvFilePath);
const csvWriter = createObjectCsvWriter({
  path: csvFilePath,
  header: [
    {id: 'username', title: 'Username'},
    {id: 'bio', title: 'Bio'},
    {id: 'query', title: 'Query'}
  ],
  append: true
});

if (!fileExists) {
  // If file doesn't exist, write the header row first
  await csvWriter.writeRecords([]);
}

// We'll search for users mentioning these phrases in their bios
const queries = [
  "class of 2025",
  "class of 2026",
  "class of 2027",
  "class of 2028"
];

// Each query can go through multiple pages (max 10 pages, each with up to 100 results)
const maxPages = 10;
const perPage = 100;

// Build a list of tasks (query-page pairs)
const tasks = [];
for (const query of queries) {
  for (let page = 1; page <= maxPages; page++) {
    tasks.push({ query, page });
  }
}

// Helper to fetch and filter one page of results
async function fetchUserPage({ query, page }) {
  console.log(`Fetching page ${page} for query "${query}"...`);
  const url = `https://hcer-public-github-data.a.selfhosted.hackclub.com/gh/search/users?q=${encodeURIComponent(query + " in:bio")}&per_page=${perPage}&page=${page}`;
  
  const resp = await fetch(url, {
    headers: {
      'X-Proxy-API-Key': API_KEY
    }
  });

  if (!resp.ok) {
    console.error(`Request failed for page=${page}, query="${query}", status=${resp.status}`);
    return [];
  }

  const data = await resp.json();

  if (!data.items) {
    console.warn(`No items found for page ${page}, query "${query}"`);
    return [];
  }

  console.log(`Found ${data.items.length} users on page ${page} for query "${query}"`);

  // Filter out bios that contain "PhD" or "high school" (case-insensitive)
  const userDetails = [];
  let processedCount = 0;
  for (const item of data.items) {
    processedCount++;
    if (processedCount % 10 === 0) {
      console.log(`Processing user ${processedCount}/${data.items.length} on page ${page} for query "${query}"`);
    }

    // We'll need to fetch each user's bio from the user API
    const userUrl = `https://hcer-public-github-data.a.selfhosted.hackclub.com/gh/users/${item.login}`;
    const userResp = await fetch(userUrl, {
      headers: {
        'X-Proxy-API-Key': API_KEY
      }
    });
    if (userResp.ok) {
      const userData = await userResp.json();
      const bio = userData.bio || "";
      // Exclude "PhD" and "high school" in a case-insensitive manner
      if (!/phd/i.test(bio) && !/high school/i.test(bio)) {
        userDetails.push({ 
          username: item.login, 
          bio,
          query
        });
      }
    } else {
      console.warn(`Failed to fetch details for user ${item.login}: ${userResp.status}`);
    }
  }

  console.log(`Found ${userDetails.length} matching users on page ${page} for query "${query}"`);
  return userDetails;
}

// For concurrency in batches of 32
const concurrency = 32;
async function processTasksInBatches(tasksArray, batchSize) {
  console.log(`Processing ${tasksArray.length} total tasks in batches of ${batchSize}`);
  let totalProcessed = 0;
  let totalSaved = 0;

  for (let i = 0; i < tasksArray.length; i += batchSize) {
    const batch = tasksArray.slice(i, i + batchSize);
    console.log(`\nStarting batch ${Math.floor(i/batchSize) + 1}/${Math.ceil(tasksArray.length/batchSize)}`);
    
    const results = await Promise.all(batch.map(fetchUserPage));
    const flattened = results.flat();
    
    totalProcessed += batch.length;
    if (flattened.length > 0) {
      await csvWriter.writeRecords(flattened);
      totalSaved += flattened.length;
      console.log(`Saved ${flattened.length} users (${totalSaved} total saved)`);
    }
    
    console.log(`Completed ${totalProcessed}/${tasksArray.length} tasks (${Math.round(totalProcessed/tasksArray.length*100)}%)`);
  }

  console.log(`\nFinal Summary:`);
  console.log(`Total tasks processed: ${totalProcessed}`);
  console.log(`Total users saved: ${totalSaved}`);
}

console.log("Starting undergrad student source script...");
console.log(`Queries to process: ${queries.join(", ")}`);

// Run the tasks in batches
await processTasksInBatches(tasks, concurrency);

console.log("Done sourcing undergrad students.");