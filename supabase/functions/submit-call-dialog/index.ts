// supabase/functions/submit-call-dialog/index.ts
// Secure endpoint for Flutter app to submit verified phone call log match + post-call dialog together.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing Authorization header" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const body = await req.json();
    const {
      dial_attempt_id,
      device_id,
      number_e164,
      call_type,
      started_at,
      duration_secs,
      sim_slot,
      clock_skew_secs,
      caller_claimed_connected,
      outcome,
      reason_ids,
      other_reason_text,
      note,
      seconds_after_call_end,
      follow_up_due_at,
      follow_up_type,
    } = body;

    // Basic payload validations
    if (!dial_attempt_id || !device_id || !number_e164 || !outcome || !reason_ids) {
      return new Response(JSON.stringify({ error: "Missing required call dialog fields." }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Call the database function
    const { data, error } = await supabase.rpc("submit_call_dialog", {
      p_dial_attempt_id: dial_attempt_id,
      p_device_id: device_id,
      p_number_e164: number_e164,
      p_call_type: call_type || "outgoing",
      p_started_at: started_at,
      p_duration_secs: duration_secs ?? 0,
      p_sim_slot: sim_slot ?? null,
      p_clock_skew_secs: clock_skew_secs ?? 0,
      p_caller_claimed_connected: Boolean(caller_claimed_connected),
      p_outcome: outcome,
      p_reason_ids: reason_ids,
      p_other_reason_text: other_reason_text ?? null,
      p_note: note ?? null,
      p_seconds_after_call_end: seconds_after_call_end ?? null,
      p_follow_up_due_at: follow_up_due_at ?? null,
      p_follow_up_type: follow_up_type ?? null,
    });

    if (error) {
      return new Response(JSON.stringify({ error: error.message }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify(data), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Internal Server Error";
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
