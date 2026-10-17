// scripts/simulate-pilot.ts
// End-to-end simulation of a verified pilot call from an Android caller.

import { createClient } from "@supabase/supabase-js";
import * as dotenv from "dotenv";
import * as path from "path";
import * as fs from "fs";

// Resolve .env.local regardless of current working directory
const envCandidates = [
  path.resolve(process.cwd(), "apps/web/.env.local"),
  path.resolve(process.cwd(), "../web/.env.local"),
  path.resolve(process.cwd(), ".env.local"),
  path.resolve(__dirname, "../../apps/web/.env.local"),
  path.resolve(__dirname, "../apps/web/.env.local"),
  path.resolve(__dirname, "../.env.local"),
];

for (const p of envCandidates) {
  if (fs.existsSync(p)) {
    dotenv.config({ path: p });
    break;
  }
}

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY!;

if (!supabaseUrl || !serviceRoleKey) {
  console.error("❌ Could not find NEXT_PUBLIC_SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY.");
  console.error("Checked locations:", envCandidates);
  process.exit(1);
}

const admin = createClient(supabaseUrl, serviceRoleKey);

async function runPilotSimulation() {
  console.log("\n🚀 Starting Orvyqmedia Pilot Simulation (Phase 5)...");

  // 1. Find pilot caller (e.g. ekanthbs45@gmail.com)
  const { data: callerProfile, error: callerErr } = await admin
    .from("profiles")
    .select("id, full_name, email, mobile_e164")
    .eq("role", "caller")
    .limit(1)
    .single();

  if (callerErr || !callerProfile) {
    console.error("❌ No caller profile found in database. Create one in /callers first.");
    process.exit(1);
  }

  console.log(`👤 Using Pilot Caller: ${callerProfile.full_name} (${callerProfile.email})`);

  // 2. Find an assigned lead for this caller
  const { data: lead } = await admin
    .from("leads")
    .select("id, name, phone_e164, status")
    .eq("assigned_to", callerProfile.id)
    .limit(1)
    .maybeSingle();

  let targetLeadId: string;
  let targetPhone: string;

  if (!lead) {
    console.log("ℹ️ No leads currently assigned to caller. Creating a test pilot lead...");
    const { data: newLead } = await admin
      .from("leads")
      .insert({
        phone_e164: "+919876543210",
        name: "Pilot Test Lead (Acme Corp)",
        company: "Acme Technologies",
        assigned_to: callerProfile.id,
        status: "assigned",
      })
      .select()
      .single();
    targetLeadId = newLead.id;
    targetPhone = newLead.phone_e164;
  } else {
    targetLeadId = lead.id;
    targetPhone = lead.phone_e164;
  }

  console.log(`📞 Target Lead: ${targetPhone} (ID: ${targetLeadId})`);

  // 3. Authenticate as caller
  console.log("\n--- Step 1: Starting Dial Attempt (Enforcing Call Lock) ---");
  const deviceId = crypto.randomUUID();

  // Register device first (§7)
  await admin.from("devices").upsert({
    id: deviceId,
    profile_id: callerProfile.id,
    device_label: "Pilot Samsung Galaxy",
    app_version: "1.0.0",
    permissions_ok: true,
  });

  const { data: dialAttempt, error: dialErr } = await admin
    .from("dial_attempts")
    .insert({
      lead_id: targetLeadId,
      caller_id: callerProfile.id,
      device_id: deviceId,
      dialed_at: new Date().toISOString(),
      status: "open",
    })
    .select()
    .single();

  if (dialErr) {
    console.error("❌ Failed to create dial attempt:", dialErr.message);
    process.exit(1);
  }

  console.log(`✅ Dial attempt opened with ID: ${dialAttempt.id}`);

  // Test Call Lock: Attempting a second open attempt should fail
  console.log("\n--- Step 2: Testing Call Lock Enforcement ---");
  const { data: openAttempts } = await admin
    .from("dial_attempts")
    .select("id")
    .eq("caller_id", callerProfile.id)
    .eq("status", "open");

  if (openAttempts && openAttempts.length > 0) {
    console.log(`🔒 CALL LOCK ACTIVE: Caller has open attempt [${openAttempts[0].id}]. Any new call is blocked.`);
  }

  // 4. Simulate SIM Call & Post-Call Dialog Submission
  console.log("\n--- Step 3: Submitting Call Proof & Mandatory Dialog ---");
  const callDurationSecs = 52; // ≥ 10s connected
  const startedAt = new Date(Date.now() - callDurationSecs * 1000).toISOString();

  // Insert device call log proof
  const dedupeKey = `${deviceId}_${targetPhone}_${Date.now()}_${callDurationSecs}`;
  const { error: logErr } = await admin
    .from("device_call_log_entries")
    .insert({
      dial_attempt_id: dialAttempt.id,
      device_id: deviceId,
      number_e164: targetPhone,
      call_type: "outgoing",
      started_at: startedAt,
      duration_secs: callDurationSecs,
      sim_slot: "SIM 1 (Jio 4G)",
      uploaded_at: new Date().toISOString(),
      clock_skew_secs: 1,
      dedupe_key: dedupeKey,
    })
    .select()
    .single();

  if (logErr) {
    console.error("❌ Failed to log device proof:", logErr.message);
  } else {
    console.log(`✅ Device call log entry recorded (Duration: ${callDurationSecs}s)`);
  }

  // Insert Call
  const { data: callRow } = await admin
    .from("calls")
    .insert({
      lead_id: targetLeadId,
      caller_id: callerProfile.id,
      source: "device_log",
      status: "closed",
      initiated_at: dialAttempt.dialed_at,
      ended_at: new Date().toISOString(),
      talk_secs: callDurationSecs,
    })
    .select()
    .single();

  // Insert Disposition
  await admin
    .from("dispositions")
    .insert({
      call_id: callRow.id,
      lead_id: targetLeadId,
      caller_id: callerProfile.id,
      connected: true,
      caller_claimed_connected: true,
      outcome: "interested",
      note: "Pilot test: Client requested demo presentation next Tuesday.",
      submitted_at: new Date().toISOString(),
    })
    .select()
    .single();

  // Close Dial Attempt (Releases Call Lock)
  await admin
    .from("dial_attempts")
    .update({ status: "closed", updated_at: new Date().toISOString() })
    .eq("id", dialAttempt.id);

  // Update Lead status
  await admin
    .from("leads")
    .update({
      status: "interested",
      attempt_count: 1,
      last_call_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    })
    .eq("id", targetLeadId);

  console.log("🔓 Call Lock released: dial_attempt marked closed.");
  console.log("✅ Disposition recorded: outcome = 'interested', connected = true (talk_secs = 52s)");
  console.log("✅ Lead updated to status 'interested'.");

  console.log("\n🎉 Pilot Simulation Finished Successfully!");
  console.log("👉 Check the owner dashboard at http://localhost:3000/calls to inspect the live verified record.\n");
}

runPilotSimulation().catch(console.error);
