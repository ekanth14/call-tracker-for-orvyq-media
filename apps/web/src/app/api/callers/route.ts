import { NextRequest, NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

export async function POST(req: NextRequest) {
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
    const { email, password, full_name, mobile_e164 } = body;

    if (!email || !password || !full_name) {
      return NextResponse.json(
        { error: "Email, password, and full name are required." },
        { status: 400 }
      );
    }

    const admin = createAdminClient();

    // 3. Create user in auth
    let userId: string | null = null;
    const { data: authUser, error: authError } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: {
        full_name,
        role: "caller",
        mobile_e164: mobile_e164 || null,
      },
    });

    if (authError) {
      const isAlreadyRegistered =
        authError.message.toLowerCase().includes("already registered") ||
        authError.message.toLowerCase().includes("already been registered");

      if (isAlreadyRegistered) {
        const { data: userList } = await admin.auth.admin.listUsers();
        const existing = userList?.users?.find(
          (u) => u.email?.toLowerCase() === email.toLowerCase()
        );
        if (existing) {
          userId = existing.id;
          await admin.auth.admin.updateUserById(existing.id, {
            password,
            user_metadata: {
              full_name,
              role: "caller",
              mobile_e164: mobile_e164 || null,
            },
          });
        } else {
          return NextResponse.json({ error: authError.message }, { status: 400 });
        }
      } else {
        return NextResponse.json({ error: authError.message }, { status: 400 });
      }
    } else {
      userId = authUser.user.id;
    }

    if (!userId) {
      return NextResponse.json({ error: "Failed to establish user account." }, { status: 500 });
    }

    // 4. Ensure profiles table row exists with role caller
    const { error: profileError } = await admin.from("profiles").upsert({
      id: userId,
      full_name,
      email,
      role: "caller",
      mobile_e164: mobile_e164 || null,
      is_active: true,
    });

    if (profileError) {
      return NextResponse.json({ error: profileError.message }, { status: 400 });
    }

    return NextResponse.json({
      success: true,
      user: {
        id: authUser.user.id,
        email: authUser.user.email,
        full_name,
      },
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Internal Server Error";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

export async function PATCH(req: NextRequest) {
  try {
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

    const { caller_id, is_active } = await req.json();

    if (!caller_id || typeof is_active !== "boolean") {
      return NextResponse.json({ error: "Invalid parameters" }, { status: 400 });
    }

    const admin = createAdminClient();
    const { error } = await admin
      .from("profiles")
      .update({ is_active, updated_at: new Date().toISOString() })
      .eq("id", caller_id);

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }

    return NextResponse.json({ success: true, is_active });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Internal Server Error";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
