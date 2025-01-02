CREATE OR REPLACE VIEW "CommitsByUser" AS
SELECT 
  c.id,
  c.sha,
  COALESCE(
    (c."rawData"->>'author'->>'login')::text,
    (c."rawData"->>'commit'->>'author'->>'name')::text
  ) as "authorName",
  (c."rawData"->>'author'->>'id')::integer as "authorId",
  (c."rawData"->>'commit'->>'message')::text as message,
  c."createdAt"
FROM "Commit" c; 