import { NextRequest, NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

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

    const { data: profile } = await serverSupabase
      .from("profiles")
      .select("role")
      .eq("id", user.id)
      .single();

    if (profile?.role !== "owner") {
      return NextResponse.json(
        { error: "Forbidden: Only owners/admins can edit team messages." },
        { status: 403 }
      );
    }

    // 2. Parse request payload
    const body = await req.json();
    const { messageId, content } = body;

    if (!messageId || typeof content !== "string" || !content.trim()) {
      return NextResponse.json(
        { error: "messageId and non-empty content are required." },
        { status: 400 }
      );
    }

    const trimmedContent = content.trim();

    // 3. Attempt update with authenticated owner client first
    // This provides auth.uid() in Postgres, satisfying the trigger's is_owner() check
    let updateResult = await serverSupabase
      .from("team_messages")
      .update({
        content: trimmedContent,
        is_edited: true,
        edited_at: new Date().toISOString(),
      })
      .eq("id", messageId)
      .select()
      .single();

    if (updateResult.error && updateResult.error.message.includes("is_edited")) {
      // Column may not be migrated yet in database
      updateResult = await serverSupabase
        .from("team_messages")
        .update({ content: trimmedContent })
        .eq("id", messageId)
        .select()
        .single();
    }

    // Fallback to admin client if serverSupabase was blocked by client policy
    if (updateResult.error) {
      const admin = createAdminClient();
      let adminResult = await admin
        .from("team_messages")
        .update({
          content: trimmedContent,
          is_edited: true,
          edited_at: new Date().toISOString(),
        })
        .eq("id", messageId)
        .select()
        .single();

      if (adminResult.error && adminResult.error.message.includes("is_edited")) {
        adminResult = await admin
          .from("team_messages")
          .update({ content: trimmedContent })
          .eq("id", messageId)
          .select()
          .single();
      }

      if (adminResult.error) {
        return NextResponse.json(
          { error: updateResult.error.message || adminResult.error.message },
          { status: 500 }
        );
      }

      updateResult = adminResult;
    }

    return NextResponse.json({
      success: true,
      message: {
        ...updateResult.data,
        is_edited: true,
      },
    });
  } catch (err: any) {
    return NextResponse.json(
      { error: err?.message || "Internal server error" },
      { status: 500 }
    );
  }
}

export async function DELETE(req: NextRequest) {
  try {
    // 1. Verify owner authorization
    const serverSupabase = await createClient();
    const {
      data: { user },
    } = await serverSupabase.auth.getUser();

    if (!user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const { data: profile } = await serverSupabase
      .from("profiles")
      .select("role")
      .eq("id", user.id)
      .single();

    if (profile?.role !== "owner") {
      return NextResponse.json(
        { error: "Forbidden: Only owners/admins can delete team messages." },
        { status: 403 }
      );
    }

    // 2. Parse request payload (URL param or JSON body)
    const { searchParams } = new URL(req.url);
    let messageId = searchParams.get("id");

    if (!messageId) {
      try {
        const body = await req.json();
        messageId = body.messageId;
      } catch (_) {}
    }

    if (!messageId) {
      return NextResponse.json(
        { error: "messageId is required." },
        { status: 400 }
      );
    }

    // 3. Delete using authenticated owner client first
    let { error } = await serverSupabase
      .from("team_messages")
      .delete()
      .eq("id", messageId);

    // Fallback to admin client if needed
    if (error) {
      const admin = createAdminClient();
      const adminRes = await admin
        .from("team_messages")
        .delete()
        .eq("id", messageId);
      error = adminRes.error;
    }

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }

    return NextResponse.json({
      success: true,
      messageId,
    });
  } catch (err: any) {
    return NextResponse.json(
      { error: err?.message || "Internal server error" },
      { status: 500 }
    );
  }
}
