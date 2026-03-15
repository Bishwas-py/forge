# Cross-Check Rules Reference

Detailed rules for the three-layer cross-check in Phase 4 Step 5. For every data point extracted from the UI, compare it against the API response and the database row. Use the categories below to classify each comparison and determine severity.

---

## 1. UI vs API

Compare every value displayed in the UI to the corresponding field in the raw API response.

### What to check

- For each number, string, date, or status rendered in the UI, locate the matching field in the API JSON response.
- Compare values after accounting for known formatting: the UI may add currency symbols, thousand separators, or percentage signs that the API returns as raw numbers.
- Flag any value where the UI shows a **different number** than the API returned.
- Flag any value where the UI shows a **different status** than the API returned.
- Flag any field present in the API response that the UI **does not display at all**.
- Flag any value displayed in the UI that **has no corresponding field** in the API response — the UI may be using cached, hardcoded, or stale data.

### Severity guidance

- **CRITICAL** — The displayed number, amount, or status is factually different from the API value.
- **WARNING** — A field exists in the API but is not rendered in the UI, or formatting lost precision.
- **INFO** — Minor label differences that do not change meaning (e.g., `"active"` vs `"Active"`).

---

## 2. UI vs DB

Compare every value displayed in the UI to the corresponding column in the database row.

### What to check

- For each value in the UI, locate the matching row and column in the database.
- Account for formatting: DB stores raw values, UI applies formatting.
- After accounting for formatting, the underlying value must match.
- Flag any status where the DB enum does not map to the displayed label.
- Flag any count in the UI that disagrees with the DB row count.

### Severity guidance

- **CRITICAL** — The displayed value is factually wrong compared to the DB.
- **WARNING** — Values mismatch after accounting for formatting, or counts disagree due to filtering.
- **INFO** — Cosmetic differences where meaning is preserved.

---

## 3. API vs DB

Compare every field in the API response to the corresponding column in the database.

### What to check

- The API reads from the DB, so these should match closely. Any disagreement indicates a backend bug.
- Flag stale API values (DB updated but API returns old data).
- Flag differing result counts (API filters vs direct DB query).
- Flag computed/derived fields that don't match manual DB calculations.

### Severity guidance

- **CRITICAL** — API returns a different value than the DB stores.
- **CRITICAL** — Records exist in DB but API omits them without auth/soft-delete reason.
- **WARNING** — API applies undocumented filters causing count mismatches.
- **INFO** — Minor serialization differences (timestamp format).

---

## 4. Rounding

### What to check

- Compare at raw precision first. If DB stores `84.995`, API should return `84.995`.
- **Currency** — must display exactly 2 decimal places. Check rounding method (round half up, not truncation).
- **Percentages** — check if context expects integer or decimal display. `0.155` shown as `15%` = precision lost.
- **Quantities** — should be whole numbers. `3.7` shown as `3` = truncation bug.

### Severity guidance

- **CRITICAL** — Rounding error changes monetary value by >= $0.01.
- **CRITICAL** — Percentage wrong by >= 1 whole point.
- **WARNING** — Rounding loses meaningful precision but magnitude is correct.
- **INFO** — Display precision differs but rounded value is mathematically correct.

---

## 5. Timezone

### What to check

- DB stores UTC. UI may display local time. Verify conversion is correct.
- Check date component first — UTC near midnight may shift calendar day.
- Check time component — verify offset applied correctly.
- Check relative times ("3 hours ago") against UTC timestamp.
- Date-only fields should NOT have timezone offsets applied.

### Severity guidance

- **CRITICAL** — Displayed date is a different calendar day than correct local date.
- **WARNING** — Time component is wrong but date is correct.
- **WARNING** — Date-only DB field has timezone offset applied.
- **INFO** — Time displayed without timezone indicator.

---

## 6. Empty States

### What to check

- If UI shows empty state ("No results"), verify DB actually has no matching data.
- **DB has rows but UI shows "No results"** = BUG.
- **API returns empty array but DB has rows** = API BUG.
- **API returns data but UI shows "No results"** = FRONTEND BUG.
- Check pagination edge cases.

### Severity guidance

- **CRITICAL** — DB has data but UI shows empty state.
- **CRITICAL** — API returns empty but DB has matching data.
- **WARNING** — API returns data but UI shows "No results".
- **INFO** — Empty state flickers during loading.

---

## 7. Silent Fallbacks

### What to check

- Check if any API call returned 4xx/5xx but UI shows data instead of an error.
- Check for null API fields where UI shows concrete values (not "N/A" but actual data).
- Check for network failures with no UI error state.
- Check for stale data from previous successful load.
- Check for loading states that never resolve.

### Severity guidance

- **CRITICAL** — UI shows data from a failed API call without error indication.
- **WARNING** — Null field displayed with fallback that could be mistaken for real data.
- **WARNING** — Network request failed but no UI error state.
- **INFO** — UI shows "—" or "N/A" for null field.

---

## 8. Missing Data

### What to check

- List every non-null DB column. Compare to API response fields. Flag omissions.
- Compare API response fields to UI display. Flag unrendered fields.
- Distinguish intentional security omissions (password_hash, api_key) from bugs.

### Severity guidance

- **WARNING** — Non-sensitive, user-relevant field populated in DB but not displayed.
- **WARNING** — Field in API response but not rendered in UI.
- **INFO** — Field intentionally excluded for security.

---

## 9. Count Mismatches

### What to check

- **Header count vs rendered items** — "24 items" header but 20 items rendered.
- **Pagination** — "Showing 1-10 of 50" — verify 10 items displayed, total matches API and DB.
- **Filtered vs total confusion** — search returns 12 but header shows 50 (unfiltered total).
- **Badge counts** — notification badge number vs actual items.
- **Aggregation** — "5 active, 3 pending, 2 completed" should add to total.

### Severity guidance

- **CRITICAL** — Displayed total is wrong compared to actual items.
- **CRITICAL** — Category counts don't add up to total.
- **WARNING** — Pagination metadata inconsistent.
- **INFO** — Minor count inconsistencies that resolve after refresh.

---

## 10. Status Mapping

### What to check

- Build mapping table: each DB status value → UI label.
- Check for inconsistent mappings (same status, different labels on different pages).
- Check for unmapped statuses (DB value with no UI representation).
- Check for wrong mappings (`failed` shown as "Completed").
- Check color/badge consistency across pages.

### Severity guidance

- **CRITICAL** — DB status maps to wrong UI label.
- **CRITICAL** — DB status has no UI representation, records invisible.
- **WARNING** — Same status maps to different labels on different pages.
- **WARNING** — Status qualifier lost (`pending_review` shown as "Pending").
- **INFO** — Minor spelling/capitalization differences.
- **INFO** — Visual inconsistency (different badge colors for same status).
