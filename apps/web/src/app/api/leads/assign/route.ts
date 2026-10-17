import { NextRequest, NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

export async function POST(req: NextRequest) {
  try {
    // 1. Verify owner
    const serverSupabase = await createClient();
    const {
      data: { user },
    } = await serverSupabase.auth.getUser();

    if (!user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const { data: ownerProfile } = await serverSupabase
      .from("profiles")
      .select("role")
      .eq("id", user.id)
      .single();

    if (ownerProfile?.role !== "owner") {
      return NextResponse.json({ error: "Forbidden: Owner only" }, { status: 403 });
    }

    const body = await req.json();
    const {
      type, // 'single' | 'bulk' | 'even_split'
      lead_id,
      lead_ids,
      caller_id,
      caller_ids,
    } = body;

    const admin = createAdminClient();

    // Case 1: Single assignment
    if (type === "single") {
      if (!lead_id) {
        return NextResponse.json({ error: "lead_id is required" }, { status: 400 });
      }

      const newStatus = caller_id ? "assigned" : "new";
      const { error } = await admin
        .from("leads")
        .update({
          assigned_to: caller_id || null,
          assigned_at: caller_id ? new Date().toISOString() : null,
          status: newStatus,
          updated_at: new Date().toISOString(),
        })
        .eq("id", lead_id);

      if (error) {
        return NextResponse.json({ error: error.message }, { status: 500 });
      }

      return NextResponse.json({ success: true, lead_id, caller_id });
    }

    // Case 2: Bulk assignment to a single caller (or unassigning)
    if (type === "bulk") {
      if (!lead_ids || !Array.isArray(lead_ids) || lead_ids.length === 0) {
        return NextResponse.json({ error: "lead_ids array is required" }, { status: 400 });
      }

      const newStatus = caller_id ? "assigned" : "new";
      const { error } = await admin
        .from("leads")
        .update({
          assigned_to: caller_id || null,
          assigned_at: caller_id ? new Date().toISOString() : null,
          status: newStatus,
          updated_at: new Date().toISOString(),
        })
        .in("id", lead_ids);

      if (error) {
        return NextResponse.json({ error: error.message }, { status: 500 });
      }

      return NextResponse.json({ success: true, count: lead_ids.length, caller_id });
    }

    // Case 3: Even Split among multiple callers
    if (type === "even_split") {
      if (!caller_ids || !Array.isArray(caller_ids) || caller_ids.length === 0) {
        return NextResponse.json(
          { error: "At least one caller must be selected for even split." },
          { status: 400 }
        );
      }

      let targetLeadIds: string[] = [];

      if (lead_ids && Array.isArray(lead_ids) && lead_ids.length > 0) {
        targetLeadIds = lead_ids;
      } else {
        // Fetch all unassigned new leads
        const { data: pending, error: pendingErr } = await admin
          .from("leads")
          .select("id")
          .is("assigned_to", null)
          .eq("status", "new");

        if (pendingErr) {
          return NextResponse.json({ error: pendingErr.message }, { status: 500 });
        }
        targetLeadIds = (pending || []).map((p) => p.id);
      }

      if (targetLeadIds.length === 0) {
        return NextResponse.json(
          { error: "No leads available to distribute." },
          { status: 400 }
        );
      }

      // Group leads round-robin by caller
      const callerBuckets: Record<string, string[]> = {};
      caller_ids.forEach((cId) => {
        callerBuckets[cId] = [];
      });

      targetLeadIds.forEach((leadId, idx) => {
        const callerId = caller_ids[idx % caller_ids.length];
        callerBuckets[callerId].push(leadId);
      });

      // Update each bucket
      const now = new Date().toISOString();
      const assignmentSummary: Record<string, number> = {};

      for (const [cId, ids] of Object.entries(callerBuckets)) {
        if (ids.length > 0) {
          const { error: splitErr } = await admin
            .from("leads")
            .update({
              assigned_to: cId,
              assigned_at: now,
              status: "assigned",
              updated_at: now,
            })
            .in("id", ids);

          if (splitErr) {
            return NextResponse.json({ error: splitErr.message }, { status: 500 });
          }
          assignmentSummary[cId] = ids.length;
        }
      }

      return NextResponse.json({
        success: true,
        total_distributed: targetLeadIds.length,
        callers_count: caller_ids.length,
        distribution: assignmentSummary,
      });
    }

    return NextResponse.json({ error: "Invalid assignment type" }, { status: 400 });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Internal Server Error";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
