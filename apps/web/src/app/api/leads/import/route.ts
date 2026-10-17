import { NextRequest, NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import { normalizePhoneE164 } from "@/lib/phone";

interface ImportLeadItem {
  phone_raw: string;
  name?: string;
  company?: string;
  notes?: string;
}

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
      leads,
      batch_name,
      duplicate_strategy = "skip", // 'skip' | 'update' | 'reject'
    }: {
      leads: ImportLeadItem[];
      batch_name?: string;
      duplicate_strategy?: "skip" | "update" | "reject";
    } = body;

    if (!leads || !Array.isArray(leads) || leads.length === 0) {
      return NextResponse.json({ error: "No leads provided for import." }, { status: 400 });
    }

    const admin = createAdminClient();

    // 2. Normalize numbers to E.164
    const validLeads: Array<{
      phone_e164: string;
      name: string | null;
      company: string | null;
      notes: string | null;
    }> = [];
    const invalidRows: Array<{ raw: string; error: string }> = [];

    // Deduplicate within the uploaded payload itself
    const seenInPayload = new Set<string>();

    for (const item of leads) {
      const norm = normalizePhoneE164(item.phone_raw);
      if (!norm.success || !norm.e164) {
        invalidRows.push({
          raw: item.phone_raw,
          error: norm.error || "Invalid phone number",
        });
        continue;
      }

      if (seenInPayload.has(norm.e164)) {
        continue; // skip payload duplicate
      }
      seenInPayload.add(norm.e164);

      validLeads.push({
        phone_e164: norm.e164,
        name: item.name?.trim() || null,
        company: item.company?.trim() || null,
        notes: item.notes?.trim() || null,
      });
    }

    if (validLeads.length === 0) {
      return NextResponse.json(
        {
          error: "All provided phone numbers were invalid.",
          invalidRows,
        },
        { status: 400 }
      );
    }

    // 3. Check for existing duplicates in DB
    const phoneList = validLeads.map((l) => l.phone_e164);
    const { data: existingLeads, error: queryError } = await admin
      .from("leads")
      .select("phone_e164, id")
      .in("phone_e164", phoneList);

    if (queryError) {
      return NextResponse.json({ error: queryError.message }, { status: 500 });
    }

    const existingSet = new Set((existingLeads || []).map((e) => e.phone_e164));

    if (duplicate_strategy === "reject" && existingSet.size > 0) {
      return NextResponse.json(
        {
          error: `Import rejected: ${existingSet.size} numbers already exist in the database.`,
          existingDuplicates: Array.from(existingSet),
        },
        { status: 400 }
      );
    }

    // 4. Create Batch record
    const finalBatchName =
      batch_name?.trim() || `Import - ${new Date().toLocaleDateString("en-IN", { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" })}`;

    const { data: batch, error: batchError } = await admin
      .from("lead_batches")
      .insert({
        name: finalBatchName,
        source: "web_import",
        created_by: user.id,
      })
      .select()
      .single();

    if (batchError) {
      return NextResponse.json({ error: batchError.message }, { status: 500 });
    }

    // 5. Filter or prepare leads to insert
    let toInsert: Array<{
      batch_id: string;
      phone_e164: string;
      name: string | null;
      company: string | null;
      notes: string | null;
      status: "new";
    }> = [];

    let skippedCount = 0;
    let updatedCount = 0;

    for (const lead of validLeads) {
      const isExisting = existingSet.has(lead.phone_e164);
      if (isExisting) {
        if (duplicate_strategy === "skip") {
          skippedCount++;
          continue;
        } else if (duplicate_strategy === "update") {
          // Update notes / metadata on existing
          await admin
            .from("leads")
            .update({
              name: lead.name || undefined,
              company: lead.company || undefined,
              notes: lead.notes || undefined,
              updated_at: new Date().toISOString(),
            })
            .eq("phone_e164", lead.phone_e164);
          updatedCount++;
          continue;
        }
      }

      toInsert.push({
        batch_id: batch.id,
        phone_e164: lead.phone_e164,
        name: lead.name,
        company: lead.company,
        notes: lead.notes,
        status: "new",
      });
    }

    // Chunked insert if large
    if (toInsert.length > 0) {
      const chunkSize = 200;
      for (let i = 0; i < toInsert.length; i += chunkSize) {
        const chunk = toInsert.slice(i, i + chunkSize);
        const { error: insertError } = await admin.from("leads").insert(chunk);
        if (insertError) {
          return NextResponse.json({ error: insertError.message }, { status: 500 });
        }
      }
    }

    return NextResponse.json({
      success: true,
      batch_id: batch.id,
      batch_name: finalBatchName,
      total_received: leads.length,
      imported: toInsert.length,
      skipped_duplicates: skippedCount,
      updated_duplicates: updatedCount,
      invalid_numbers: invalidRows.length,
      invalidRows: invalidRows.slice(0, 10), // sample errors
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Internal Server Error";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
