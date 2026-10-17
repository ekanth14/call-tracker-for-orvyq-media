import { describe, it, expect } from "vitest";
import { normalizePhoneE164 } from "../src/lib/phone";

describe("Phone Normalization (India E.164)", () => {
  it("normalizes a standard 10-digit Indian mobile number", () => {
    const res = normalizePhoneE164("9876543210");
    expect(res.success).toBe(true);
    expect(res.e164).toBe("+919876543210");
    expect(res.country).toBe("IN");
  });

  it("handles numbers starting with 6, 7, 8, and 9", () => {
    expect(normalizePhoneE164("6301234567").e164).toBe("+916301234567");
    expect(normalizePhoneE164("7012345678").e164).toBe("+917012345678");
    expect(normalizePhoneE164("8123456789").e164).toBe("+918123456789");
    expect(normalizePhoneE164("9123456780").e164).toBe("+919123456780");
  });

  it("normalizes numbers with leading 0 (trunk code)", () => {
    const res = normalizePhoneE164("09876543210");
    expect(res.success).toBe(true);
    expect(res.e164).toBe("+919876543210");
  });

  it("normalizes numbers with 91 prefix without plus", () => {
    const res = normalizePhoneE164("919876543210");
    expect(res.success).toBe(true);
    expect(res.e164).toBe("+919876543210");
  });

  it("normalizes numbers already having +91 prefix", () => {
    const res = normalizePhoneE164("+919876543210");
    expect(res.success).toBe(true);
    expect(res.e164).toBe("+919876543210");
  });

  it("cleans spaces, dashes, dots, and parentheses", () => {
    const res1 = normalizePhoneE164("+91 98765-43210");
    expect(res1.success).toBe(true);
    expect(res1.e164).toBe("+919876543210");

    const res2 = normalizePhoneE164("(09876) 543 210");
    expect(res2.success).toBe(true);
    expect(res2.e164).toBe("+919876543210");

    const res3 = normalizePhoneE164("98765.43210");
    expect(res3.success).toBe(true);
    expect(res3.e164).toBe("+919876543210");
  });

  it("rejects invalid or too short numbers", () => {
    const res1 = normalizePhoneE164("12345");
    expect(res1.success).toBe(false);

    const res2 = normalizePhoneE164("abc123xyz");
    expect(res2.success).toBe(false);

    const res3 = normalizePhoneE164("");
    expect(res3.success).toBe(false);

    const res4 = normalizePhoneE164(null);
    expect(res4.success).toBe(false);
  });
});
