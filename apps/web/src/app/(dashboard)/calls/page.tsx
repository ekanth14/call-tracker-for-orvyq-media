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
  Download,
  Flame,
  Activity,
  BarChart3,
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
    reason_ids?: string[];
  };
  flags?: Array<{
    id: string;
    rule_code: string;
    severity: string;
    details?: any;
  }>;
}

export default function CallsPage() {
  const [calls, setCalls] = useState<CallRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState("");
  const [outcomeFilter, setOutcomeFilter] = useState("all");
  const [flagFilter, setFlagFilter] = useState("all");

  const fetchCalls = async () => {
    setLoading(true);
    const supabase = createClient();

    // Query calls with related lead, caller profile, disposition, and flags (§7 & §8)
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
        disposition:dispositions(id, connected, caller_claimed_connected, outcome, note, submitted_at, reason_ids),
        flags(id, rule_code, severity, details)
      `)
      .order("initiated_at", { ascending: false })
      .limit(200);

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

  // Metrics computation for Phase 4 (§8)
  const totalCallsCount = calls.length;
  const connectedCallsCount = calls.filter(
    (c) => (c.disposition?.connected ?? c.talk_secs >= 10)
  ).length;
  const totalTalkSeconds = calls.reduce((acc, c) => acc + (c.talk_secs || 0), 0);
  const totalTalkHours = (totalTalkSeconds / 3600).toFixed(1);
  const connectionRate =
    totalCallsCount > 0
      ? Math.round((connectedCallsCount / totalCallsCount) * 100)
      : 0;
  const totalFlagsCount = calls.filter(
    (c) => c.flags && c.flags.length > 0
  ).length;

  const exportToCSV = () => {
    if (calls.length === 0) return;

    const headers = [
      "Call ID",
      "Initiated At",
      "Caller Name",
      "Caller Email",
      "Lead Phone",
      "Lead Name",
      "Lead Company",
      "Talk Seconds",
      "Connected (≥10s)",
      "Outcome",
      "Flags",
      "Notes",
    ];

    const rows = calls.map((c) => [
      `"${c.id}"`,
      `"${c.initiated_at}"`,
      `"${c.caller?.full_name || ""}"`,
      `"${c.caller?.email || ""}"`,
      `"${c.lead?.phone_e164 || ""}"`,
      `"${c.lead?.name || ""}"`,
      `"${c.lead?.company || ""}"`,
      c.talk_secs,
      c.disposition?.connected ? "TRUE" : "FALSE",
      `"${c.disposition?.outcome || "pending"}"`,
      `"${(c.flags || []).map((f) => f.rule_code).join("; ")}"`,
      `"${(c.disposition?.note || "").replace(/"/g, '""')}"`,
    ]);

    const csvContent = [headers.join(","), ...rows.map((r) => r.join(","))].join(
      "\n"
    );

    const blob = new Blob([csvContent], { type: "text/csv;charset=utf-8;" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.setAttribute("href", url);
    link.setAttribute(
      "download",
      `orvyq_calls_export_${new Date().toISOString().slice(0, 10)}.csv`
    );
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
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

    const matchesFlags =
      flagFilter === "all"
        ? true
        : flagFilter === "flagged"
        ? (c.flags?.length ?? 0) > 0
        : (c.flags?.length ?? 0) === 0;

    return matchesSearch && matchesOutcome && matchesFlags;
  });

  return (
    <div className="p-8 max-w-7xl mx-auto space-y-6">
      {/* Top Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-slate-900">
            Call Log & Audit Proofs
          </h1>
          <p className="mt-1 text-sm text-slate-500">
            Audit verified calls made by callers from their Android devices. Proofs are validated against the 10-second connected threshold (§5.1 & §8).
          </p>
        </div>

        <div className="flex items-center gap-3">
          <button
            onClick={exportToCSV}
            disabled={calls.length === 0}
            className="inline-flex items-center gap-2 px-4 py-2.5 rounded-xl font-medium text-sm text-white bg-slate-900 hover:bg-slate-800 disabled:opacity-50 transition shadow-sm"
          >
            <Download className="h-4 w-4" />
            Export CSV
          </button>
          <button
            onClick={fetchCalls}
            className="inline-flex items-center gap-2 px-4 py-2.5 rounded-xl font-medium text-sm text-slate-700 bg-white border border-slate-200 hover:bg-slate-50 transition shadow-sm"
          >
            <RefreshCw className="h-4 w-4" />
            Refresh
          </button>
        </div>
      </div>

      {/* Metrics Summary Strip (Phase 4 KPIs) */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <div className="bg-white p-4 rounded-xl border border-slate-200/80 shadow-sm">
          <div className="flex items-center justify-between text-slate-500 text-xs font-semibold uppercase">
            <span>Total Calls</span>
            <PhoneCall className="h-4 w-4 text-blue-500" />
          </div>
          <div className="mt-2 text-2xl font-extrabold text-slate-900">
            {totalCallsCount}
          </div>
          <div className="text-[11px] text-slate-400 mt-0.5">Logged with proofs</div>
        </div>

        <div className="bg-white p-4 rounded-xl border border-slate-200/80 shadow-sm">
          <div className="flex items-center justify-between text-slate-500 text-xs font-semibold uppercase">
            <span>Connection Rate</span>
            <Activity className="h-4 w-4 text-emerald-500" />
          </div>
          <div className="mt-2 text-2xl font-extrabold text-emerald-600">
            {connectionRate}%
          </div>
          <div className="text-[11px] text-slate-400 mt-0.5">≥10s connected talk time</div>
        </div>

        <div className="bg-white p-4 rounded-xl border border-slate-200/80 shadow-sm">
          <div className="flex items-center justify-between text-slate-500 text-xs font-semibold uppercase">
            <span>Total Talk Time</span>
            <Clock className="h-4 w-4 text-indigo-500" />
          </div>
          <div className="mt-2 text-2xl font-extrabold text-slate-900">
            {totalTalkHours} hrs
          </div>
          <div className="text-[11px] text-slate-400 mt-0.5">{totalTalkSeconds} seconds logged</div>
        </div>

        <div className="bg-white p-4 rounded-xl border border-slate-200/80 shadow-sm">
          <div className="flex items-center justify-between text-slate-500 text-xs font-semibold uppercase">
            <span>Audit Flags</span>
            <AlertTriangle className="h-4 w-4 text-rose-500" />
          </div>
          <div className="mt-2 text-2xl font-extrabold text-rose-600">
            {totalFlagsCount}
          </div>
          <div className="text-[11px] text-slate-400 mt-0.5">Discrepancies flagged</div>
        </div>
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

        <div className="flex items-center gap-3 w-full md:w-auto">
          {/* Outcome Filter */}
          <select
            value={outcomeFilter}
            onChange={(e) => setOutcomeFilter(e.target.value)}
            className="px-3 py-2 rounded-xl border border-slate-200 bg-slate-50 text-xs font-medium text-slate-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 w-full md:w-auto"
          >
            <option value="all">All Outcomes</option>
            <option value="interested">Interested</option>
            <option value="not_interested">Not Interested</option>
            <option value="unreachable">Unreachable / Ringing</option>
            <option value="wrong_number">Wrong Number</option>
          </select>

          {/* Audit Flag Filter (§8) */}
          <select
            value={flagFilter}
            onChange={(e) => setFlagFilter(e.target.value)}
            className="px-3 py-2 rounded-xl border border-slate-200 bg-slate-50 text-xs font-medium text-slate-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 w-full md:w-auto"
          >
            <option value="all">All Audit Statuses</option>
            <option value="flagged">Flagged Calls Only</option>
            <option value="clean">Clear Calls Only</option>
          </select>
        </div>
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
            <h3 className="font-bold text-slate-800 text-base">No Calls Match Filters</h3>
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
                  <th className="py-3.5 px-6">Talk Duration</th>
                  <th className="py-3.5 px-6">System Finding</th>
                  <th className="py-3.5 px-6">Outcome</th>
                  <th className="py-3.5 px-6">Audit Flags</th>
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
                        <div>{formatDuration(call.talk_secs)}</div>
                        {call.source === "device_log" ? (
                          <div className="inline-flex items-center gap-1 text-[10px] font-semibold text-emerald-700 bg-emerald-50 px-1.5 py-0.5 rounded border border-emerald-200 mt-1">
                            <Smartphone className="h-3 w-3" /> Hardware Verified (SIM Log)
                          </div>
                        ) : (
                          <div className="inline-flex items-center gap-1 text-[10px] font-semibold text-amber-700 bg-amber-50 px-1.5 py-0.5 rounded border border-amber-200 mt-1">
                            <AlertTriangle className="h-3 w-3" /> Unverified / Manual
                          </div>
                        )}
                      </td>
                      <td className="py-4 px-6">
                        {call.source === "manual" ? (
                          <span className="inline-flex items-center gap-1 text-xs font-medium text-amber-700 bg-amber-50 px-2 py-0.5 rounded-full border border-amber-200">
                            <AlertTriangle className="h-3 w-3" /> Unverified Manual Entry
                          </span>
                        ) : disp?.connected ? (
                          <span className="inline-flex items-center gap-1 text-xs font-medium text-emerald-700 bg-emerald-50 px-2 py-0.5 rounded-full border border-emerald-200">
                            <CheckCircle2 className="h-3 w-3" /> Duration ≥10s (Threshold Met)
                          </span>
                        ) : (
                          <span className="inline-flex items-center gap-1 text-xs font-medium text-slate-500 bg-slate-100 px-2 py-0.5 rounded-full border border-slate-200">
                            <XCircle className="h-3 w-3" /> Under 10s Minimum
                          </span>
                        )}
                      </td>
                      <td className="py-4 px-6">
                        {disp ? (
                          <div>
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
                            {disp.note && (
                              <div className="text-[11px] text-slate-400 mt-1 max-w-xs truncate">
                                "{disp.note}"
                              </div>
                            )}
                          </div>
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
                                title={JSON.stringify(f.details || {})}
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
