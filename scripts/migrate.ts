// scripts/migrate.ts
// Applies supabase/combined_migrations.sql using a Postgres connection string.

import { Client } from "pg";
import * as fs from "fs";
import * as path from "path";
import * as dotenv from "dotenv";

dotenv.config({ path: path.resolve(process.cwd(), ".env.local") });
dotenv.config({ path: path.resolve(process.cwd(), ".env") });

async function runMigration() {
  const dbUrl = process.env.DATABASE_URL;

  if (!dbUrl) {
    console.log("\n⚠️ DATABASE_URL is not set in your .env.local file.");
    console.log("   To run migrations automatically from the terminal, add your Postgres connection string to .env.local:");
    console.log("   DATABASE_URL=postgres://postgres.[project-ref]:[DB-PASSWORD]@aws-0-[region].pooler.supabase.com:6543/postgres\n");
    console.log("👉 Or simply copy and paste supabase/combined_migrations.sql into the Supabase Dashboard SQL Editor:");
    console.log("   https://supabase.com/dashboard/project/iewenwzafmcrjkjhtwzv/sql/new\n");
    process.exit(1);
  }

  const sqlPath = path.resolve(process.cwd(), "supabase/combined_migrations.sql");
  const sql = fs.readFileSync(sqlPath, "utf-8");

  console.log("\n🚀 Connecting to PostgreSQL database...");
  const client = new Client({
    connectionString: dbUrl,
    ssl: { rejectUnauthorized: false },
  });

  await client.connect();
  console.log("✅ Connected successfully. Applying combined_migrations.sql...");

  await client.query(sql);
  console.log("🎉 Migrations applied successfully!\n");

  await client.end();
}

runMigration().catch((err) => {
  console.error("❌ Migration failed:", err.message);
  process.exit(1);
});
