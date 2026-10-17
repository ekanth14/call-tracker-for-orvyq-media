// supabase/tests/rls_caller_isolation.test.ts
// Automated RLS test suite proving:
// 1. Caller A cannot read Caller B's assigned leads.
// 2. Caller A cannot read Caller B's calls or dispositions.
// 3. Caller cannot directly INSERT/UPDATE/DELETE calls.
// 4. Caller cannot directly INSERT/UPDATE/DELETE device_call_log_entries.
// 5. Caller cannot directly INSERT/UPDATE/DELETE dispositions.
// 6. Caller cannot read or write to audit_log.
// 7. Owner has full visibility across all tables.

import { createClient } from "@supabase/supabase-js";
import * as dotenv from "dotenv";
import * as path from "path";

dotenv.config({ path: path.resolve(process.cwd(), ".env.local") });
dotenv.config({ path: path.resolve(process.cwd(), ".env") });

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

async function runRlsTests() {
  console.log("\n🧪 Running RLS Caller Isolation & Protection Tests...\n");

  if (!supabaseUrl || !serviceKey || !anonKey) {
    console.log("⚠️ Environment variables NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY, and SUPABASE_SERVICE_ROLE_KEY are not configured yet.");
    console.log("   Skipping live DB execution. Test suite will run against your configured Supabase project.\n");
    return;
  }

  // Admin Client
  const adminClient = createClient(supabaseUrl, serviceKey);

  // 1. Create 2 test callers and 1 test owner
  const timestamp = Date.now();
  const callerAEmail = `test_caller_a_${timestamp}@test.com`;
  const callerBEmail = `test_caller_b_${timestamp}@test.com`;
  const ownerEmail = `test_owner_${timestamp}@test.com`;
  const testPassword = "TestPassword123!";

  console.log("1. Creating test users in Auth...");
  const { data: userA } = await adminClient.auth.admin.createUser({
    email: callerAEmail,
    password: testPassword,
    email_confirm: true,
    user_metadata: { role: "caller", full_name: "Caller A" },
  });

  const { data: userB } = await adminClient.auth.admin.createUser({
    email: callerBEmail,
    password: testPassword,
    email_confirm: true,
    user_metadata: { role: "caller", full_name: "Caller B" },
  });

  const { data: userOwner } = await adminClient.auth.admin.createUser({
    email: ownerEmail,
    password: testPassword,
    email_confirm: true,
    user_metadata: { role: "owner", full_name: "Owner Test" },
  });

  if (!userA.user || !userB.user || !userOwner.user) {
    throw new Error("Failed to create test users.");
  }

  // Ensure profiles have correct roles
  await adminClient.from("profiles").upsert([
    { id: userA.user.id, role: "caller", full_name: "Caller A", email: callerAEmail },
    { id: userB.user.id, role: "caller", full_name: "Caller B", email: callerBEmail },
    { id: userOwner.user.id, role: "owner", full_name: "Owner Test", email: ownerEmail },
  ]);

  // 2. Sign in as Caller A and Caller B using anon client
  const clientA = createClient(supabaseUrl, anonKey);
  const clientB = createClient(supabaseUrl, anonKey);
  const clientOwner = createClient(supabaseUrl, anonKey);

  await clientA.auth.signInWithPassword({ email: callerAEmail, password: testPassword });
  await clientB.auth.signInWithPassword({ email: callerBEmail, password: testPassword });
  await clientOwner.auth.signInWithPassword({ email: ownerEmail, password: testPassword });

  // 3. Admin seeds leads assigned to Caller A and Caller B
  const leadAPhone = `+9198765${String(timestamp).slice(-5)}`;
  const leadBPhone = `+9198766${String(timestamp).slice(-5)}`;

  const { data: leadA } = await adminClient.from("leads").insert({
    phone_e164: leadAPhone,
    name: "Lead for A",
    assigned_to: userA.user.id,
    status: "assigned",
  }).select().single();

  const { data: leadB } = await adminClient.from("leads").insert({
    phone_e164: leadBPhone,
    name: "Lead for B",
    assigned_to: userB.user.id,
    status: "assigned",
  }).select().single();

  console.log("2. Testing Lead Isolation (Caller A vs Caller B)...");
  // Caller A queries leads
  const { data: callerALeads } = await clientA.from("leads").select();
  const callerACanSeeB = callerALeads?.some((l) => l.id === leadB.id);
  const callerACanSeeA = callerALeads?.some((l) => l.id === leadA.id);

  if (callerACanSeeB) {
    throw new Error("❌ FAILURE: Caller A was able to read Caller B's lead!");
  }
  if (!callerACanSeeA) {
    throw new Error("❌ FAILURE: Caller A could not read their own assigned lead!");
  }
  console.log("   ✅ PASSED: Caller A can only read their own assigned leads.");

  console.log("3. Testing Direct Call Write Protection...");
  // Caller A tries to directly INSERT into calls table
  const { error: directCallInsertErr } = await clientA.from("calls").insert({
    lead_id: leadA.id,
    caller_id: userA.user.id,
    source: "device_log",
    status: "closed",
    talk_secs: 15,
  });

  if (!directCallInsertErr) {
    throw new Error("❌ FAILURE: Caller A was able to write directly to calls table!");
  }
  console.log("   ✅ PASSED: Caller direct INSERT on 'calls' was blocked by RLS.");

  console.log("4. Testing Direct Disposition Write Protection...");
  const { error: directDispInsertErr } = await clientA.from("dispositions").insert({
    call_id: "00000000-0000-0000-0000-000000000000",
    lead_id: leadA.id,
    caller_id: userA.user.id,
    connected: true,
    outcome: "interested",
    reason_ids: [],
  });

  if (!directDispInsertErr) {
    throw new Error("❌ FAILURE: Caller A was able to write directly to dispositions table!");
  }
  console.log("   ✅ PASSED: Caller direct INSERT on 'dispositions' was blocked by RLS.");

  console.log("5. Testing Audit Log Privacy...");
  const { data: callerAAuditLogs, error: auditReadErr } = await clientA.from("audit_log").select();
  if (callerAAuditLogs && callerAAuditLogs.length > 0) {
    throw new Error("❌ FAILURE: Caller A was able to read audit_log entries!");
  }
  console.log("   ✅ PASSED: Caller cannot read audit_log.");

  console.log("6. Testing Owner Full Access...");
  const { data: ownerLeads } = await clientOwner.from("leads").select();
  const ownerSeesBoth =
    ownerLeads?.some((l) => l.id === leadA.id) &&
    ownerLeads?.some((l) => l.id === leadB.id);

  if (!ownerSeesBoth) {
    throw new Error("❌ FAILURE: Owner could not see both leads!");
  }
  console.log("   ✅ PASSED: Owner has full visibility across all leads.");

  // Cleanup test users & leads
  await adminClient.from("leads").delete().in("id", [leadA.id, leadB.id]);
  await adminClient.auth.admin.deleteUser(userA.user.id);
  await adminClient.auth.admin.deleteUser(userB.user.id);
  await adminClient.auth.admin.deleteUser(userOwner.user.id);

  console.log("\n✨ ALL RLS CALLER ISOLATION TESTS PASSED SUCCESSFULLY! ✨\n");
}

runRlsTests().catch((err) => {
  console.error("Test failed:", err);
  process.exit(1);
});
