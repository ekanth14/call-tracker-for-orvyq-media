// scripts/create-owner.ts
// Bootstraps the first Owner account using the Supabase Service Role Key.

import { createClient } from "@supabase/supabase-js";
import * as dotenv from "dotenv";
import * as path from "path";

// Load environment variables from .env.local or .env
dotenv.config({ path: path.resolve(process.cwd(), ".env.local") });
dotenv.config({ path: path.resolve(process.cwd(), ".env") });

async function createOwner() {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!supabaseUrl || !serviceRoleKey) {
    console.error("❌ Error: NEXT_PUBLIC_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set in your .env or .env.local");
    process.exit(1);
  }

  // Parse command line arguments: e.g. tsx scripts/create-owner.ts --email=owner@example.com --password=secret --name="Owner"
  const args = process.argv.slice(2);
  const emailArg = args.find((a) => a.startsWith("--email="))?.split("=")[1];
  const passArg = args.find((a) => a.startsWith("--password="))?.split("=")[1];
  const nameArg = args.find((a) => a.startsWith("--name="))?.split("=")[1] || "Owner Admin";
  const mobileArg = args.find((a) => a.startsWith("--mobile="))?.split("=")[1];

  const email = emailArg || process.env.OWNER_EMAIL || "owner@orvyqmedia.com";
  const password = passArg || process.env.OWNER_PASSWORD || "OrvyqSecure2026!";
  const fullName = nameArg;

  console.log(`\n🚀 Initializing First Owner Creation for: ${email}...`);

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });

  // Check if user already exists
  const { data: existingUsers, error: listError } = await supabase.auth.admin.listUsers();
  if (listError) {
    console.error("❌ Failed to query existing users:", listError.message);
    process.exit(1);
  }

  const existing = existingUsers.users.find((u) => u.email?.toLowerCase() === email.toLowerCase());

  let userId: string;

  if (existing) {
    console.log(`ℹ️ User ${email} already exists in auth. Updating profile to owner...`);
    userId = existing.id;
  } else {
    // Create new owner user in auth
    const { data: newUser, error: createError } = await supabase.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: {
        full_name: fullName,
        role: "owner",
        mobile_e164: mobileArg,
      },
    });

    if (createError) {
      console.error("❌ Failed to create user:", createError.message);
      process.exit(1);
    }

    userId = newUser.user.id;
    console.log(`✅ Auth user created with ID: ${userId}`);
  }

  // Ensure profile has owner role
  const { error: profileError } = await supabase.from("profiles").upsert({
    id: userId,
    full_name: fullName,
    email: email,
    role: "owner",
    is_active: true,
    mobile_e164: mobileArg || null,
    mobile_verified_at: new Date().toISOString(),
  });

  if (profileError) {
    console.error("❌ Failed to upsert owner profile:", profileError.message);
    process.exit(1);
  }

  console.log(`\n🎉 Success! Owner account is ready.`);
  console.log(`   Email: ${email}`);
  console.log(`   Role: owner`);
  console.log(`   Password: ${existing ? "[Unchanged]" : password}\n`);
}

createOwner().catch((err) => {
  console.error("Unexpected error:", err);
  process.exit(1);
});
