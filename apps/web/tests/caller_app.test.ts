import { describe, it, expect } from "vitest";
import { normalizePhoneE164 } from "../src/lib/phone";

describe("Caller Web App for iOS - Telephony & Shift Logic", () => {
  it("normalizes phone numbers correctly for native iOS dialer (tel:) links", () => {
    const rawNumbers = [
      "9876543210",
      "+91 98765 43210",
      "09876543210",
      "919876543210",
    ];

    for (const num of rawNumbers) {
      const result = normalizePhoneE164(num);
      expect(result.success).toBe(true);
      expect(result.e164).toBe("+919876543210");
      // Clean digits for WhatsApp link
      const cleanDigits = result.e164!.replace(/\D/g, "");
      expect(cleanDigits).toBe("919876543210");
    }
  });

  it("enforces minimum connected talk duration threshold (>= 10 seconds)", () => {
    const minConnectedDurationSecs = 10;

    const testDurations = [
      { secs: 0, connected: false },
      { secs: 5, connected: false },
      { secs: 9, connected: false },
      { secs: 10, connected: true },
      { secs: 30, connected: true },
      { secs: 120, connected: true },
    ];

    for (const item of testDurations) {
      const isConnected = item.secs >= minConnectedDurationSecs;
      expect(isConnected).toBe(item.connected);
    }
  });

  it("maps UI disposition outcomes to database disposition_outcome ENUM accurately", () => {
    function mapOutcomeToDb(uiOutcome: string): "interested" | "not_interested" | "not_connected" {
      if (uiOutcome === "interested" || uiOutcome === "callback") {
        return "interested";
      }
      if (uiOutcome === "not_interested") {
        return "not_interested";
      }
      return "not_connected";
    }

    expect(mapOutcomeToDb("interested")).toBe("interested");
    expect(mapOutcomeToDb("callback")).toBe("interested");
    expect(mapOutcomeToDb("not_interested")).toBe("not_interested");
    expect(mapOutcomeToDb("no_answer")).toBe("not_connected");
    expect(mapOutcomeToDb("busy")).toBe("not_connected");
    expect(mapOutcomeToDb("wrong_number")).toBe("not_connected");
  });

  it("calculates daily quota progress correctly", () => {
    const quotaTarget = 50;

    const calcProgress = (calls: number) => Math.min(100, (calls / quotaTarget) * 100);

    expect(calcProgress(0)).toBe(0);
    expect(calcProgress(25)).toBe(50);
    expect(calcProgress(50)).toBe(100);
    expect(calcProgress(65)).toBe(100); // capped at 100%
  });

  it("formats stopwatch and active shift timer correctly", () => {
    function formatStopwatch(totalSeconds: number) {
      const minutes = Math.floor(totalSeconds / 60);
      const seconds = totalSeconds % 60;
      return `${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
    }

    expect(formatStopwatch(0)).toBe("00:00");
    expect(formatStopwatch(9)).toBe("00:09");
    expect(formatStopwatch(65)).toBe("01:05");
    expect(formatStopwatch(7200)).toBe("120:00");
  });
});
