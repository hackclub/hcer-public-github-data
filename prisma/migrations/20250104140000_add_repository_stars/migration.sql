-- Add stars column to Repository table
ALTER TABLE "Repository" ADD COLUMN "stars" INTEGER NOT NULL DEFAULT 0;

-- Update existing repositories with star counts from their API response data
-- Using COALESCE to handle null values and a CASE statement for type checking
UPDATE "Repository" r
SET stars = COALESCE(
  CASE 
    WHEN jsonb_typeof(ar."responseBody"->>'stargazers_count') = 'number' 
    THEN (ar."responseBody"->>'stargazers_count')::integer
    ELSE 0
  END,
  0
)
FROM "APIRequest" ar
WHERE ar.id = r."fetchedFromRequestId"; 