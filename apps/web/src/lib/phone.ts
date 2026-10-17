import { parsePhoneNumberFromString, CountryCode } from "libphonenumber-js";

export interface PhoneNormalizationResult {
  success: boolean;
  e164?: string;
  formatted?: string;
  country?: string;
  raw: string;
  error?: string;
}

/**
 * Normalizes any phone number string to E.164 format.
 * Defaults to India (IN / +91).
 * Handles common Indian formats:
 * - 10 digits: "9876543210" -> "+919876543210"
 * - Leading zero: "09876543210" -> "+919876543210"
 * - Prefix with 91 without plus: "919876543210" -> "+919876543210"
 * - Formatted with punctuation: "+91 (987) 654-3210" -> "+919876543210"
 */
export function normalizePhoneE164(
  input: string | number | null | undefined,
  defaultCountry: CountryCode = "IN"
): PhoneNormalizationResult {
  if (input === null || input === undefined) {
    return { success: false, raw: "", error: "Phone number is empty" };
  }

  const rawStr = String(input).trim();
  if (!rawStr) {
    return { success: false, raw: "", error: "Phone number is empty" };
  }

  // Remove common invisible characters, tabs, spaces, dashes, parentheses
  let cleaned = rawStr.replace(/[\s\-\(\)\.\/\\_]/g, "");

  // Special handling for India when default is 'IN'
  if (defaultCountry === "IN") {
    // If starts with 0091, replace with +91
    if (cleaned.startsWith("0091")) {
      cleaned = "+" + cleaned.slice(2);
    }
    // If starts with +0, remove the 0
    else if (cleaned.startsWith("+0")) {
      cleaned = "+" + cleaned.slice(2);
    }
    // If 11 digits starting with 0 (e.g. 09876543210)
    else if (/^0[6-9]\d{9}$/.test(cleaned)) {
      cleaned = "+91" + cleaned.slice(1);
    }
    // If 12 digits starting with 91 without plus (e.g. 919876543210)
    else if (/^91[6-9]\d{9}$/.test(cleaned)) {
      cleaned = "+" + cleaned;
    }
    // If standard 10 digit Indian mobile (starting with 6, 7, 8, 9)
    else if (/^[6-9]\d{9}$/.test(cleaned)) {
      cleaned = "+91" + cleaned;
    }
  }

  try {
    const phoneNumber = parsePhoneNumberFromString(cleaned, defaultCountry);

    if (phoneNumber && phoneNumber.isValid()) {
      return {
        success: true,
        e164: phoneNumber.number, // E.164 format: e.g. +919876543210
        formatted: phoneNumber.formatInternational(), // e.g. +91 98765 43210
        country: phoneNumber.country || defaultCountry,
        raw: rawStr,
      };
    }

    // Secondary heuristic fallback for 10-digit Indian numbers if libphonenumber was strict
    if (defaultCountry === "IN" && /^\+91[6-9]\d{9}$/.test(cleaned)) {
      return {
        success: true,
        e164: cleaned,
        formatted: `+91 ${cleaned.slice(3, 8)} ${cleaned.slice(8)}`,
        country: "IN",
        raw: rawStr,
      };
    }

    return {
      success: false,
      raw: rawStr,
      error: `Invalid phone number format for country ${defaultCountry}`,
    };
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Parsing error";
    return {
      success: false,
      raw: rawStr,
      error: message,
    };
  }
}
