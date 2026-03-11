import { describe, it, expect } from "vitest";
import { formatHours } from "./formatters.js";

describe("formatHours", () => {
  describe("basic formatting", () => {
    it("formats fractional hours as rounded hours", () => {
      expect(formatHours(0.5)).toBe("1h");
      expect(formatHours(0.25)).toBe("0h");
      expect(formatHours(0.75)).toBe("1h");
    });

    it("rounds to nearest hour", () => {
      expect(formatHours(0.4)).toBe("0h");
      expect(formatHours(0.6)).toBe("1h");
    });

    it("handles zero hours", () => {
      expect(formatHours(0)).toBe("0h");
    });

    it("handles very small values", () => {
      expect(formatHours(0.001)).toBe("0h");
      expect(formatHours(0.4)).toBe("0h");
    });

    it("formats whole hours", () => {
      expect(formatHours(1)).toBe("1h");
      expect(formatHours(5)).toBe("5h");
      expect(formatHours(12)).toBe("12h");
      expect(formatHours(23)).toBe("23h");
    });

    it("rounds fractional hours to nearest whole hour", () => {
      expect(formatHours(1.3)).toBe("1h");
      expect(formatHours(1.5)).toBe("2h");
      expect(formatHours(2.7)).toBe("3h");
      expect(formatHours(12.1)).toBe("12h");
    });
  });

  describe("large values", () => {
    it("formats hours >= 24 as hours only", () => {
      expect(formatHours(24)).toBe("24h");
      expect(formatHours(25)).toBe("25h");
      expect(formatHours(25.5)).toBe("26h");
      expect(formatHours(48)).toBe("48h");
      expect(formatHours(72)).toBe("72h");
    });

    it("rounds fractional hours to nearest whole hour", () => {
      expect(formatHours(24.3)).toBe("24h");
      expect(formatHours(24.6)).toBe("25h");
      expect(formatHours(25.7)).toBe("26h");
    });

    it("handles very large values", () => {
      expect(formatHours(168)).toBe("168h"); // 1 week
      expect(formatHours(720)).toBe("720h"); // 30 days
      expect(formatHours(8760)).toBe("8760h"); // 1 year
    });
  });

  describe("edge cases", () => {
    it("handles negative values gracefully", () => {
      expect(formatHours(-1)).toBe("-1h");
      expect(formatHours(-24)).toBe("-24h");
      expect(formatHours(-25.5)).toBe("-25h");
    });

    it("handles decimal precision edge cases", () => {
      expect(formatHours(1.9999)).toBe("2h");
      expect(formatHours(0.99999)).toBe("1h");
      expect(formatHours(23.9999)).toBe("24h");
    });
  });

  describe("with includeMinutes option", () => {
    it("formats hours with minutes when includeMinutes is true", () => {
      expect(formatHours(1.5, { includeMinutes: true })).toBe("1h 30m");
      expect(formatHours(2.25, { includeMinutes: true })).toBe("2h 15m");
      expect(formatHours(3.75, { includeMinutes: true })).toBe("3h 45m");
    });

    it("formats whole hours without minutes", () => {
      expect(formatHours(1, { includeMinutes: true })).toBe("1h");
      expect(formatHours(5, { includeMinutes: true })).toBe("5h");
      expect(formatHours(24, { includeMinutes: true })).toBe("24h");
    });

    it("rounds minutes correctly", () => {
      expect(formatHours(1.501, { includeMinutes: true })).toBe("1h 30m");
      expect(formatHours(1.499, { includeMinutes: true })).toBe("1h 30m");
      expect(formatHours(1.008, { includeMinutes: true })).toBe("1h");
    });

    it("handles edge case where minutes round to 60", () => {
      expect(formatHours(1.999, { includeMinutes: true })).toBe("2h");
      expect(formatHours(23.999, { includeMinutes: true })).toBe("24h");
    });

    it("works with large hour values", () => {
      expect(formatHours(25.5, { includeMinutes: true })).toBe("25h 30m");
      expect(formatHours(168.25, { includeMinutes: true })).toBe("168h 15m");
      expect(formatHours(720.75, { includeMinutes: true })).toBe("720h 45m");
    });

    it("handles negative values with minutes", () => {
      expect(formatHours(-1.5, { includeMinutes: true })).toBe("-1h 30m");
      expect(formatHours(-24.25, { includeMinutes: true })).toBe("-24h 15m");
    });

    it("uses default behavior when includeMinutes is false", () => {
      expect(formatHours(1.5, { includeMinutes: false })).toBe("2h");
      expect(formatHours(2.25, { includeMinutes: false })).toBe("2h");
    });

    it("uses default behavior when no options provided", () => {
      expect(formatHours(1.5)).toBe("2h");
      expect(formatHours(2.25)).toBe("2h");
    });
  });
});
