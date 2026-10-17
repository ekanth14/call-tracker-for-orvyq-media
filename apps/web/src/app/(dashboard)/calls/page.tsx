"use client";

import React, { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import {
  PhoneCall,
  Search,
  Filter,
  CheckCircle2,
  XCircle,
  AlertTriangle,
  Clock,
  Smartphone,
  ShieldCheck,
  RefreshCw,
  Loader2,
} from "lucide-react";

interface CallRow {
  id: string;
  source: string;
  status: string;
  initiated_at: string;
  ended_at: string | null;
  talk_secs: number;
  lead?: {
    id: string;
    phone_e164: string;
    name: string | null;
    company: string | null;
  };
  caller?: {
    id: string;
    full_name: string;
    email: string | null;
  };
  disposition?: {
    id: string;
    connected: boolean;
    caller_claimed_connected: boolean | null;
    outcome: string;
    note: string | null;
    submitted_at: string;
  };
  flags?: Array<{
    id: string;
    rule_code: string;
    severity: string;
  }>;
}

export default function CallsPage() {
  const [calls, setCalls] = useState<CallRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState("");
  const [outcomeFilter, setOutcomeFilter] = useState("all");

  const fetchCalls = async () => {
    setLoading(true);
    const supabase = createClient();

    // Query calls with related lead, caller profile, and disposition
    const { data, error } = await supabase
      .from("calls")
      .select(`
        id,
        source,
        status,
        initiated_at,
        ended_at,
        talk_secs,
        lead:leads(id, phone_e164, name, company),
        caller:profiles!calls_caller_id_fkey(id, full_name, email),
        disposition:dispositions(id, connected, caller_claimed_connected, outcome, note, submitted_at),
        flags(id, rule_code, severity)
      `)
      .order("initiated_at", { ascending: false })
      .limit(100);

    if (error) {
      console.error("Error fetching calls:", error);
    } else if (data) {
      setCalls(data as any);
    }
    setLoading(false);
  };

  useEffect(() => {
    fetchCalls();
  }, []);

  const formatDuration = (secs: number) => {
    const m = Math.floor(secs / 60);
    const s = secs % 60;
    return `${m}:${s < 10 ? "0" : ""}${s}`;
  };

  const filteredCalls = calls.filter((c) => {
    const leadMatch =
      c.lead?.phone_e164.includes(search) ||
      (c.lead?.name && c.lead.name.toLowerCase().includes(search.toLowerCase()));
    const callerMatch =
      c.caller?.full_name.toLowerCase().includes(search.toLowerCase()) ||
      c.caller?.email?.toLowerCase().includes(search.toLowerCase());

    const matchesSearch = leadMatch || callerMatch;
    const matchesOutcome =
      outcomeFilter === "all" || c.disposition?.outcome === outcomeFilter;

    return matchesSearch && matchesOutcome;
  });

  return (
    <div className="p-8 max-w-7xl mx-auto space-y-6">
      {/* Top Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-slate-900">
            Call Log & Proofs
          </h1>
          <p className="mt-1 text-sm text-slate-500">
            Audit verified calls made by callers from their Android devices. Proofs are validated against the 10-second connected threshold.
          </p>
        </div>

        <button
          onClick={fetchCalls}
          className="inline-flex items-center gap-2 px-4 py-2.5 rounded-xl font-medium text-sm text-slate-700 bg-white border border-slate-200 hover:bg-slate-50 transition shadow-sm"
        >
          <RefreshCw className="h-4 w-4" />
          Refresh Calls
        </button>
      </div>

      {/* Filter / Search Bar */}
      <div className="bg-white p-4 rounded-2xl border border-slate-200/80 shadow-sm flex flex-col md:flex-row items-center gap-4 justify-between">
        <div className="relative flex-1 w-full">
          <Search className="h-4 w-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2" />
          <input
            type="text"
            placeholder="Search by caller name, lead number, or client..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full pl-9 pr-4 py-2 rounded-xl bg-slate-50 border border-slate-200 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:bg-white transition"
          />
        </div>

        <select
          value={outcomeFilter}
          onChange={(e) => setOutcomeFilter(e.target.value)}
          className="px-3 py-2 rounded-xl border border-slate-200 bg-slate-50 text-xs font-medium text-slate-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 w-full md:w-auto"
        >
          <option value="all">All Outcomes</option>
          <option value="interested">Interested</option>
          <option value="not_interested">Not Interested</option>
          <option value="not_connected">Not Connected</option>
        </select>
      </div>

      {/* Calls Table */}
      <div className="bg-white rounded-2xl border border-slate-200/80 shadow-sm overflow-hidden">
        {loading ? (
          <div className="p-16 text-center text-slate-500 flex flex-col items-center justify-center gap-3">
            <Loader2 className="h-6 w-6 animate-spin text-indigo-600" />
            <span className="text-sm">Fetching call records...</span>
          </div>
        ) : filteredCalls.length === 0 ? (
          <div className="p-16 text-center text-slate-500">
            <div className="h-12 w-12 rounded-2xl bg-indigo-50 text-indigo-600 flex items-center justify-center mx-auto mb-3 shadow-inner">
              <PhoneCall className="h-6 w-6" />
            </div>
            <h3 className="font-bold text-slate-800 text-base">No Calls Recorded Yet</h3>
            <p className="text-xs text-slate-400 mt-1.5 max-w-md mx-auto leading-relaxed">
              When callers tap <b>Call</b> on their Android device, dial the lead, and submit their mandatory post-call dialog, verified call records and duration proofs will appear here.
            </p>
            <div className="mt-5 inline-flex items-center gap-2 px-3 py-1.5 rounded-full bg-slate-100 text-slate-600 text-[11px] font-mono">
              <ShieldCheck className="h-3.5 w-3.5 text-indigo-600" />
              Connected threshold: 10s talk time
            </div>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left border-collapse text-sm">
              <thead>
                <tr className="bg-slate-50/80 border-b border-slate-200 text-xs font-semibold text-slate-500 uppercase tracking-wider">
                  <th className="py-3.5 px-6">Caller</th>
                  <th className="py-3.5 px-6">Lead</th>
                  <th className="py-3.5 px-6">Duration</th>
                  <th className="py-3.5 px-6">System Finding</th>
                  <th className="py-3.5 px-6">Outcome</th>
                  <th className="py-3.5 px-6">Flags</th>
                  <th className="py-3.5 px-6 text-right">Time</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {filteredCalls.map((call) => {
                  const disp = call.disposition;
                  return (
                    <tr key={call.id} className="hover:bg-slate-50/60 transition">
                      <td className="py-4 px-6">
                        <div className="font-semibold text-slate-900">
                          {call.caller?.full_name || "Unknown Caller"}
                        </div>
                        <div className="text-xs text-slate-400">
                          {call.caller?.email}
                        </div>
                      </td>
                      <td className="py-4 px-6">
                        <div className="font-mono text-xs font-bold text-slate-800">
                          {call.lead?.phone_e164 || "N/A"}
                        </div>
                        {call.lead?.name && (
                          <div className="text-xs text-slate-500 mt-0.5">
                            {call.lead.name} {call.lead.company ? `(${call.lead.company})` : ""}
                          </div>
                        )}
                      </td>
                      <td className="py-4 px-6 font-mono text-xs text-slate-700">
                        {formatDuration(call.talk_secs)}
                      </td>
                      <td className="py-4 px-6">
                        {disp?.connected ? (
                          <span className="inline-flex items-center gap-1 text-xs font-medium text-emerald-700 bg-emerald-50 px-2 py-0.5 rounded-full border border-emerald-200">
                            <CheckCircle2 className="h-3 w-3" /> Connected (&ge;10s)
                          </span>
                        ) : (
                          <span className="inline-flex items-center gap-1 text-xs font-medium text-slate-500 bg-slate-100 px-2 py-0.5 rounded-full border border-slate-200">
                            <XCircle className="h-3 w-3" /> Not Connected (&lt;10s)
                          </span>
                        )}
                      </td>
                      <td className="py-4 px-6">
                        {disp ? (
                          <span
                            className={`inline-block px-2.5 py-0.5 rounded-full text-xs font-medium ${
                              disp.outcome === "interested"
                                ? "bg-purple-50 text-purple-700 border border-purple-200"
                                : disp.outcome === "not_interested"
                                ? "bg-slate-100 text-slate-600 border border-slate-200"
                                : "bg-amber-50 text-amber-700 border border-amber-200"
                            }`}
                          >
                            {disp.outcome.replace("_", " ")}
                          </span>
                        ) : (
                          <span className="text-xs text-slate-400 italic">Pending dialog</span>
                        )}
                      </td>
                      <td className="py-4 px-6">
                        {call.flags && call.flags.length > 0 ? (
                          <div className="flex flex-wrap gap-1">
                            {call.flags.map((f) => (
                              <span
                                key={f.id}
                                className="inline-flex items-center gap-1 text-[10px] font-bold px-2 py-0.5 rounded-md bg-rose-50 text-rose-700 border border-rose-200"
                              >
                                <AlertTriangle className="h-3 w-3" />
                                {f.rule_code}
                              </span>
                            ))}
                          </div>
                        ) : (
                          <span className="text-xs text-emerald-600 font-medium">Clear</span>
                        )}
                      </td>
                      <td className="py-4 px-6 text-right text-xs text-slate-400 font-mono">
                        {new Date(call.initiated_at).toLocaleTimeString([], {
                          hour: "2-digit",
                          minute: "2-digit",
                        })}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
