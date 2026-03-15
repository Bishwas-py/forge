# Form Attack Catalog

Comprehensive catalog of wild inputs for form submission testing. When recon encounters a form, it uses these categories to systematically attack every field.

---

## 1. Empty Inputs

| Attack | Value |
|--------|-------|
| All fields empty | Submit with every field untouched |
| Single field empty | Leave one empty, fill rest with valid data |
| Only whitespace | `"   "` (spaces), `"\t\t"` (tabs), `"\n\n"` (newlines) |
| Null string literal | `"null"` |
| Undefined string literal | `"undefined"` |

### Severity

- **CRITICAL**: Empty/whitespace value accepted and stored for a required field.
- **CRITICAL**: All-empty form creates a record.
- **WARNING**: `"null"` or `"undefined"` stored as string instead of actual NULL.

---

## 2. String Attacks

| Attack | Value |
|--------|-------|
| 255 characters | `"A"` x 255 |
| 1000 characters | `"B"` x 1000 |
| 10000 characters | `"C"` x 10000 |
| HTML bold tag | `"<b>test</b>"` |
| HTML image tag | `"<img src=x onerror=alert(1)>"` |
| Script injection | `"<script>alert(1)</script>"` |
| SQL injection (quote) | `"'; DROP TABLE users; --"` |
| SQL injection (OR) | `"' OR '1'='1"` |
| SQL injection (UNION) | `"' UNION SELECT username, password FROM users --"` |
| Path traversal | `"../../../etc/passwd"` |
| CRLF injection | `"test\r\nInjected-Header: value"` |
| Null byte | `"test\x00hidden"` |
| Template injection | `"{{7*7}}"`, `"${7*7}"` |
| JSON in text field | `"{\"key\": \"value\"}"` |

### Severity

- **CRITICAL**: `<script>` stored unescaped AND rendered as HTML (XSS).
- **CRITICAL**: SQL injection causes DB error or data leak.
- **CRITICAL**: 10000-char string crashes API or DB.
- **WARNING**: HTML stored unescaped but rendered as text (stored XSS risk).
- **WARNING**: Template injection evaluates to `49`.

---

## 3. Numeric Attacks

| Attack | Value |
|--------|-------|
| Zero | `0` |
| Negative | `-1`, `-999999` |
| Max 32-bit int | `2147483647` |
| Over max 32-bit | `2147483648` |
| Max 64-bit int | `9223372036854775807` |
| Small decimal | `0.001` |
| NaN/Infinity | `"NaN"`, `"Infinity"`, `"-Infinity"` |
| Negative zero | `-0` |
| Scientific notation | `1e10`, `-1e10` |
| Negative price | `-49.99` |
| Negative quantity | `-5` |
| Fractional quantity | `2.5` |
| Leading zeros | `007` |
| Number with commas | `"1,000,000"` |

### Severity

- **CRITICAL**: Negative quantity/price accepted and stored.
- **CRITICAL**: Integer overflow causes error or silent wraparound.
- **CRITICAL**: Price of `0.00` accepted for paid item.
- **WARNING**: `"NaN"` stored as string in numeric field.

---

## 4. Date Attacks

| Attack | Value |
|--------|-------|
| Unix epoch | `"1970-01-01"` |
| Far future | `"2099-12-31"` |
| Invalid (Feb 30) | `"2026-02-30"` |
| Invalid (Feb 29 non-leap) | `"2025-02-29"` |
| Invalid month | `"2026-13-01"` |
| Past date (future-only) | `"2020-01-01"` |
| Year zero | `"0000-01-01"` |
| Text in date field | `"not a date"` |
| SQL date injection | `"2026-02-20'; DROP TABLE users; --"` |

### Severity

- **CRITICAL**: Invalid date accepted and stored.
- **CRITICAL**: Past date accepted for future-only field.
- **WARNING**: Timezone mismatch shifts stored date by one day.

---

## 5. Unicode Attacks

| Attack | Value |
|--------|-------|
| Emoji | `"\u{1F600}"` (grinning face) |
| RTL override | `"\u{202E}CRITICAL_SECURITY_ISSUE"` |
| Zero-width space | `"test\u{200B}test"` |
| Combining overload | `"a"` + 16 combining marks |
| Full-width numbers | `"\u{FF11}\u{FF12}\u{FF13}"` |
| Homoglyph | `"p\u{0430}ypal.com"` (Cyrillic `a`) |
| Null character | `"test\u{0000}test"` |
| BOM prefix | `"\u{FEFF}test"` |

### Severity

- **CRITICAL**: RTL override causes other UI text to render backwards.
- **CRITICAL**: Homoglyph accepted in URL/identifier field.
- **CRITICAL**: Null character causes data truncation.
- **WARNING**: Zero-width spaces allow visually identical duplicates.

---

## 6. Duplicate Submissions

| Attack | Procedure |
|--------|-----------|
| Double-click | Click submit twice rapidly |
| Triple submit | Click submit three times |
| Same data re-submit | Submit, navigate back, submit same data again |
| Concurrent API replay | Replay the POST 5 times via curl simultaneously |

### Severity

- **CRITICAL**: Double-click creates two records.
- **CRITICAL**: Concurrent replay creates multiple resources.
- **WARNING**: Submit button doesn't disable after first click.

---

## 7. Type Mismatches

| Attack | Field type | Value |
|--------|-----------|-------|
| Text in number | Number | `"abc"` |
| Number in email | Email | `"12345"` |
| No @ in email | Email | `"notanemail"` |
| JavaScript URL | URL | `"javascript:alert(1)"` |
| Data URL | URL | `"data:text/html,<script>alert(1)</script>"` |
| Float in integer | Integer | `"3.14"` |
| Negative unsigned | Unsigned | `"-1"` |
| HTML in email | Email | `"<script>alert(1)</script>@example.com"` |

### Severity

- **CRITICAL**: `"javascript:alert(1)"` stored as URL and rendered as link.
- **CRITICAL**: `"abc"` silently coerced to `0` in number field.
- **WARNING**: Frontend validation bypassed via direct API call.

---

## 8. Boundary Values

Discover field constraints from HTML attributes (`maxlength`, `min`, `max`, `minlength`, `required`, `pattern`) in the `browser_snapshot`.

| Attack | Value |
|--------|-------|
| Exactly at max length | `"D"` x maxlength |
| One over max length | `"D"` x (maxlength + 1) |
| One under min length | `"D"` x (minlength - 1) |
| One below min value | min - 1 |
| One above max value | max + 1 |
| Off step boundary | `10.001` when step is `0.01` |
| Empty required field | Submit empty |
| Max integer (no explicit max) | `2147483647` |
| Max integer + 1 | `2147483648` |

### Severity

- **CRITICAL**: Over-max-length value accepted and stored (data truncation without error).
- **CRITICAL**: Below-min value accepted and stored.
- **CRITICAL**: API accepts values beyond frontend limits (bypass via curl).
- **WARNING**: Off-step values silently rounded instead of rejected.

---

## General Procedure

For each form encountered:

1. **Read field constraints** from `browser_snapshot` (required, maxlength, min, max, step, pattern, type).
2. **Submit one category at a time** with other fields valid. Isolates the cause.
3. **Capture result**: `browser_snapshot` for UI, `browser_console_messages` for JS errors, `browser_network_requests` for API status.
4. **Verify storage**: replay API GET via curl, query DB directly, compare submitted vs stored.
5. **Record findings** with severity per category rules above.
