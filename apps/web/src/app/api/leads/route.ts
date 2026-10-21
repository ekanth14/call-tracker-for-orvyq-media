import { NextRequest, NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import { normalizePhoneE164 } from "@/lib/phone";

export async function PATCH(req: NextRequest) {
  try {
    // 1. Verify owner authorization
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

    // 2. Parse payload
    const body = await req.json();
    const {
      lead_id,
      name,
      phone_e164,
      company,
      city,
      status,
      assigned_to,
      notes,
      next_follow_up_at,
    } = body;

    if (!lead_id) {
      return NextResponse.json({ error: "lead_id is required." }, { status: 400 });
    }

    const updates: Record<string, any> = {
      updated_at: new Date().toISOString(),
    };

    if (typeof name === "string") {
      updates.name = name.trim();
    }

    if (typeof phone_e164 === "string" && phone_e164.trim()) {
      const normalized = normalizePhoneE164(phone_e164.trim());
      if (!normalized.success || !normalized.e164) {
        return NextResponse.json(
          { error: "Invalid phone number format. Please provide a valid 10-digit mobile number." },
          { status: 400 }
        );
      }
      updates.phone_e164 = normalized.e164;
    }

    if (company !== undefined) {
      updates.company = typeof company === "string" ? company.trim() || null : null;
    }

    if (city !== undefined) {
      updates.city = typeof city === "string" ? city.trim() || null : null;
    }

    if (typeof status === "string") {
      updates.status = status;
    }

    if (assigned_to !== undefined) {
      updates.assigned_to = assigned_to || null;
      if (assigned_to) {
        updates.assigned_at = new Date().toISOString();
      }
    }

    if (notes !== undefined) {
      updates.notes = typeof notes === "string" ? notes.trim() || null : null;
    }

    if (next_follow_up_at !== undefined) {
      updates.next_follow_up_at = next_follow_up_at ? new Date(next_follow_up_at).toISOString() : null;
    }

    // 3. Execute update via authenticated serverSupabase (with fallback to admin client)
    let { data: updated, error } = await serverSupabase
      .from("leads")
      .update(updates)
      .eq("id", lead_id)
      .select()
      .single();

    if (error) {
      const admin = createAdminClient();
      const adminRes = await admin
        .from("leads")
        .update(updates)
        .eq("id", lead_id)
        .select()
        .single();
      updated = adminRes.data;
      error = adminRes.error;
    }

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }

    return NextResponse.json({
      success: true,
      lead: updated,
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Internal Server Error";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
