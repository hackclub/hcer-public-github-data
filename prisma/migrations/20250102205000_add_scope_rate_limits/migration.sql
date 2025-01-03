-- First add the new columns with defaults
ALTER TABLE "AccessToken" ADD COLUMN "coreRateLimitRemaining" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "AccessToken" ADD COLUMN "coreRateLimitReset" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE "AccessToken" ADD COLUMN "searchRateLimitRemaining" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "AccessToken" ADD COLUMN "searchRateLimitReset" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE "AccessToken" ADD COLUMN "graphqlRateLimitRemaining" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "AccessToken" ADD COLUMN "graphqlRateLimitReset" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

-- Copy existing rate limit data to core rate limits (since most existing data is from core API)
UPDATE "AccessToken"
SET "coreRateLimitRemaining" = "rateLimitRemaining",
    "coreRateLimitReset" = "rateLimitReset";

-- Drop old columns
ALTER TABLE "AccessToken" DROP COLUMN "rateLimitRemaining";
ALTER TABLE "AccessToken" DROP COLUMN "rateLimitReset"; 