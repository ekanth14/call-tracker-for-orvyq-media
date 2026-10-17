import React from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import {
  Users,
  UserCheck,
  PhoneCall,
  CheckCircle2,
  Clock,
  ArrowUpRight,
  TrendingUp,
} from "lucide-react";

export default async function DashboardPage() {
  const supabase = await createClient();

  // Parallel queries for aggregate stats
  const [
    { count: totalLeads },
    { count: assignedLeads },
    { count: pendingLeads },
    { count: interestedLeads },
    { count: totalCallers },
    { count: totalCalls },
  ] = await Promise.all([
    supabase.from("leads").select("*", { count: "exact", head: true }),
    supabase.from("leads").select("*", { count: "exact", head: true }).not("assigned_to", "is", null),
    supabase.from("leads").select("*", { count: "exact", head: true }).is("assigned_to", null),
    supabase.from("leads").select("*", { count: "exact", head: true }).eq("status", "interested"),
    supabase.from("profiles").select("*", { count: "exact", head: true }).eq("role", "caller"),
    supabase.from("calls").select("*", { count: "exact", head: true }),
  ]);

  const cards = [
    {
      title: "Total Leads",
      value: totalLeads || 0,
      icon: Users,
      color: "text-blue-600 bg-blue-50 border-blue-100",
      description: "Imported into the pipeline",
    },
    {
      title: "Assigned Leads",
      value: assignedLeads || 0,
      icon: UserCheck,
      color: "text-emerald-600 bg-emerald-50 border-emerald-100",
      description: "Currently assigned to callers",
    },
    {
      title: "Pending / Unassigned",
      value: pendingLeads || 0,
      icon: Clock,
      color: "text-amber-600 bg-amber-50 border-amber-100",
      description: "Ready for distribution",
    },
    {
      title: "Interested Outcomes",
      value: interestedLeads || 0,
      icon: CheckCircle2,
      color: "text-purple-600 bg-purple-50 border-purple-100",
      description: "High interest conversions",
    },
    {
      title: "Active Callers",
      value: totalCallers || 0,
      icon: UserCheck,
      color: "text-indigo-600 bg-indigo-50 border-indigo-100",
      description: "Registered calling agents",
    },
    {
      title: "Verified Calls",
      value: totalCalls || 0,
      icon: PhoneCall,
      color: "text-rose-600 bg-rose-50 border-rose-100",
      description: "Logged with proof",
    },
  ];

  return (
    <div className="p-8 max-w-7xl mx-auto space-y-8">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-slate-900">
            Cold-Calling Operations
          </h1>
          <p className="mt-1 text-sm text-slate-500">
            Welcome to the Orvyqmedia owner command center. Monitor lead assignment and caller activity.
          </p>
        </div>

        <div className="flex items-center gap-3">
          <Link
            href="/leads"
            className="inline-flex items-center gap-2 px-4 py-2.5 rounded-xl font-medium text-sm text-white bg-indigo-600 hover:bg-indigo-700 transition shadow-sm"
          >
            Manage Leads
            <ArrowUpRight className="h-4 w-4" />
          </Link>
          <Link
            href="/callers"
            className="inline-flex items-center gap-2 px-4 py-2.5 rounded-xl font-medium text-sm text-slate-700 bg-white border border-slate-200 hover:bg-slate-50 transition shadow-sm"
          >
            Add Callers
          </Link>
        </div>
      </div>

      {/* Metrics Grid */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-5">
        {cards.map((card) => {
          const Icon = card.icon;
          return (
            <div
              key={card.title}
              className="bg-white p-6 rounded-2xl border border-slate-200/80 shadow-sm flex flex-col justify-between"
            >
              <div className="flex items-center justify-between">
                <span className="text-xs font-semibold uppercase tracking-wider text-slate-500">
                  {card.title}
                </span>
                <div className={`p-2.5 rounded-xl border ${card.color}`}>
                  <Icon className="h-5 w-5" />
                </div>
              </div>
              <div className="mt-4">
                <div className="text-3xl font-extrabold text-slate-900 tracking-tight">
                  {card.value.toLocaleString()}
                </div>
                <div className="mt-1 text-xs text-slate-400">
                  {card.description}
                </div>
              </div>
            </div>
          );
        })}
      </div>

      {/* Quick Launch Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div className="bg-gradient-to-br from-indigo-900 to-slate-900 p-6 rounded-2xl text-white shadow-sm flex flex-col justify-between">
          <div>
            <span className="text-xs font-semibold uppercase tracking-wider text-indigo-300">
              Lead Workflow
            </span>
            <h3 className="mt-2 text-xl font-bold">Import & Distribute</h3>
            <p className="mt-2 text-sm text-slate-300">
              Bulk paste or upload CSVs. Numbers are automatically normalized to E.164 (+91 India format) and deduplicated.
            </p>
          </div>
          <div className="mt-6">
            <Link
              href="/leads"
              className="inline-flex items-center gap-2 px-4 py-2 rounded-xl text-xs font-semibold text-slate-900 bg-white hover:bg-slate-100 transition shadow"
            >
              Open Lead Manager
              <ArrowUpRight className="h-3.5 w-3.5" />
            </Link>
          </div>
        </div>

        <div className="bg-white p-6 rounded-2xl border border-slate-200/80 shadow-sm flex flex-col justify-between">
          <div>
            <div className="flex items-center gap-2 text-emerald-600 text-xs font-semibold uppercase tracking-wider">
              <TrendingUp className="h-4 w-4" />
              Android-First Verification
            </div>
            <h3 className="mt-2 text-xl font-bold text-slate-900">
              Call-Log Integrity & Lock
            </h3>
            <p className="mt-2 text-sm text-slate-500">
              Callers cannot claim interested or skip leads without verified phone log duration (10s minimum) and submitted outcome reasons.
            </p>
          </div>
          <div className="mt-6">
            <Link
              href="/calls"
              className="inline-flex items-center gap-2 px-4 py-2 rounded-xl text-xs font-semibold text-white bg-slate-900 hover:bg-slate-800 transition"
            >
              Inspect Call Log
              <ArrowUpRight className="h-3.5 w-3.5" />
            </Link>
          </div>
        </div>
      </div>
    </div>
  );
}
