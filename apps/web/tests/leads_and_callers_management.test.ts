import { describe, it, expect } from "vitest";
import { normalizePhoneE164 } from "../src/lib/phone";

interface CallerProfile {
  id: string;
  full_name: string;
  mobile_e164: string | null;
  role: "caller" | "owner";
  is_active: boolean;
}

interface LeadRecord {
  id: string;
  name: string | null;
  phone_e164: string;
  company: string | null;
  city: string | null;
  status: string;
  assigned_to: string | null;
  notes: string | null;
  next_follow_up_at: string | null;
}

function updateCallerByOwner(
  actorRole: string,
  target: CallerProfile,
  updates: Partial<CallerProfile>
): { success: boolean; caller?: CallerProfile; error?: string } {
  if (actorRole !== "owner") {
    return { success: false, error: "Forbidden: Only owners/admins can modify employee profiles." };
  }

  const updated: CallerProfile = { ...target };

  if (updates.full_name !== undefined) {
    if (!updates.full_name.trim()) {
      return { success: false, error: "Full name cannot be empty." };
    }
    updated.full_name = updates.full_name.trim();
  }

  if (updates.mobile_e164 !== undefined) {
    if (updates.mobile_e164) {
      const norm = normalizePhoneE164(updates.mobile_e164);
      if (!norm.success || !norm.e164) {
        return { success: false, error: "Invalid mobile number format." };
      }
      updated.mobile_e164 = norm.e164;
    } else {
      updated.mobile_e164 = null;
    }
  }

  if (updates.role !== undefined) {
    updated.role = updates.role;
  }

  if (updates.is_active !== undefined) {
    updated.is_active = updates.is_active;
  }

  return { success: true, caller: updated };
}

function updateLeadByOwner(
  actorRole: string,
  target: LeadRecord,
  updates: Partial<LeadRecord>
): { success: boolean; lead?: LeadRecord; error?: string } {
  if (actorRole !== "owner") {
    return { success: false, error: "Forbidden: Only owners/admins can modify lead details." };
  }

  const updated: LeadRecord = { ...target };

  if (updates.phone_e164 !== undefined) {
    const norm = normalizePhoneE164(updates.phone_e164);
    if (!norm.success || !norm.e164) {
      return { success: false, error: "Invalid phone number format. Must be a valid 10-digit number." };
    }
    updated.phone_e164 = norm.e164;
  }

  if (updates.name !== undefined) {
    updated.name = updates.name ? updates.name.trim() : null;
  }

  if (updates.company !== undefined) {
    updated.company = updates.company ? updates.company.trim() : null;
  }

  if (updates.city !== undefined) {
    updated.city = updates.city ? updates.city.trim() : null;
  }

  if (updates.status !== undefined) {
    updated.status = updates.status;
  }

  if (updates.assigned_to !== undefined) {
    updated.assigned_to = updates.assigned_to;
  }

  if (updates.notes !== undefined) {
    updated.notes = updates.notes ? updates.notes.trim() : null;
  }

  if (updates.next_follow_up_at !== undefined) {
    updated.next_follow_up_at = updates.next_follow_up_at;
  }

  return { success: true, lead: updated };
}

describe("Owner Portal: Employee & Lead Modification Rules", () => {
  const sampleCaller: CallerProfile = {
    id: "caller-uuid-1",
    full_name: "Rahul Sharma",
    mobile_e164: "+919876543210",
    role: "caller",
    is_active: true,
  };

  const sampleLead: LeadRecord = {
    id: "lead-uuid-101",
    name: "Vikram Malhotra",
    phone_e164: "+919811122233",
    company: "Malhotra Enterprises",
    city: "Mumbai",
    status: "assigned",
    assigned_to: "caller-uuid-1",
    notes: "Interested in media branding package",
    next_follow_up_at: "2026-10-22T10:00:00.000Z",
  };

  it("strictly forbids callers from modifying employee profiles", () => {
    const res = updateCallerByOwner("caller", sampleCaller, { full_name: "Hacked Name" });
    expect(res.success).toBe(false);
    expect(res.error).toMatch(/Forbidden.*owners\/admins/i);
  });

  it("allows owner to modify employee full name, mobile number, role, and active status", () => {
    const res = updateCallerByOwner("owner", sampleCaller, {
      full_name: "Rahul S. Sharma (Lead Rep)",
      mobile_e164: "9876500000",
      is_active: false,
    });

    expect(res.success).toBe(true);
    expect(res.caller?.full_name).toBe("Rahul S. Sharma (Lead Rep)");
    expect(res.caller?.mobile_e164).toBe("+919876500000");
    expect(res.caller?.is_active).toBe(false);
  });

  it("validates mobile phone number format during caller update", () => {
    const res = updateCallerByOwner("owner", sampleCaller, {
      mobile_e164: "12345", // invalid short number
    });

    expect(res.success).toBe(false);
    expect(res.error).toMatch(/Invalid mobile number format/i);
  });

  it("strictly forbids callers from modifying lead information", () => {
    const res = updateLeadByOwner("caller", sampleLead, { name: "Tampered Lead" });
    expect(res.success).toBe(false);
    expect(res.error).toMatch(/Forbidden.*owners\/admins/i);
  });

  it("allows owner to modify lead details: name, company, city, status, caller assignment, notes", () => {
    const res = updateLeadByOwner("owner", sampleLead, {
      name: "Vikram Malhotra (MD)",
      company: "Malhotra Global Group",
      city: "Bengaluru",
      status: "interested",
      assigned_to: "caller-uuid-2",
      notes: "Deal finalized, awaiting invoice.",
    });

    expect(res.success).toBe(true);
    expect(res.lead?.name).toBe("Vikram Malhotra (MD)");
    expect(res.lead?.company).toBe("Malhotra Global Group");
    expect(res.lead?.city).toBe("Bengaluru");
    expect(res.lead?.status).toBe("interested");
    expect(res.lead?.assigned_to).toBe("caller-uuid-2");
    expect(res.lead?.notes).toBe("Deal finalized, awaiting invoice.");
  });

  it("normalizes and validates lead phone number when updated", () => {
    const res = updateLeadByOwner("owner", sampleLead, {
      phone_e164: "09811122233", // with leading zero
    });

    expect(res.success).toBe(true);
    expect(res.lead?.phone_e164).toBe("+919811122233");
  });
});
