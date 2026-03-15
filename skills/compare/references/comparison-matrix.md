# Comparison Matrix Reference

Comprehensive checklist of what to compare between two systems. Use this as a reference during both recon mode (running apps) and code mode (codebases).

---

## 1. UI & User Experience

| What to compare | How to check | Severity if different |
|-----------------|-------------|----------------------|
| Page count | Count discovered pages in each | INFO |
| Navigation structure | Compare sidebar/navbar items | WARNING if major pages missing |
| Auth flow | Compare login/signup steps | WARNING |
| Form field counts | Count inputs per form | WARNING if one has more validation |
| Loading states | Do both show spinners/skeletons? | INFO |
| Error states | Trigger errors, compare handling | WARNING |
| Empty states | Navigate to empty sections | INFO |
| Mobile responsiveness | Resize viewport, compare layout | WARNING |
| Accessibility | Compare axe-core/pa11y results | WARNING |

---

## 2. API Design

| What to compare | How to check | Severity if different |
|-----------------|-------------|----------------------|
| Endpoint count | Count unique API paths | INFO |
| Naming convention | REST naming patterns | INFO |
| Response shape | Compare JSON structure for same resource | WARNING |
| Pagination style | Offset vs cursor, page size | INFO |
| Error response format | Trigger 400/404/500, compare bodies | WARNING |
| Auth mechanism | Bearer token vs cookie vs API key | INFO |
| Rate limiting | Hit endpoints rapidly, check for 429 | WARNING if one lacks it |
| Versioning | URL path vs header vs none | INFO |

---

## 3. Security

| What to compare | How to check | Severity if different |
|-----------------|-------------|----------------------|
| Security headers | Run security-scan.sh on both | CRITICAL if one missing |
| CORS policy | Compare allowed origins | CRITICAL if one is wildcard |
| Cookie flags | Compare HttpOnly/Secure/SameSite | WARNING |
| Input validation | Submit attack payloads to both | CRITICAL if one accepts |
| Auth bypass | Try accessing protected routes unauthenticated | CRITICAL |
| SQL injection | Test both with injection payloads | CRITICAL if one vulnerable |
| XSS | Test both with script injection | CRITICAL if one vulnerable |

---

## 4. Database

| What to compare | How to check | Severity if different |
|-----------------|-------------|----------------------|
| Engine | Postgres vs MySQL vs SQLite vs Mongo | INFO |
| Schema design | Compare table/collection structures | INFO |
| Relationships | Compare FK constraints | WARNING if one lacks constraints |
| Indexes | Compare index coverage | WARNING |
| Data integrity | Run db-integrity.sh on both | CRITICAL if one has orphans |
| Migration approach | Compare migration file patterns | INFO |

---

## 5. Architecture (Code Mode)

| What to compare | How to check | Severity if different |
|-----------------|-------------|----------------------|
| Framework | Read manifests | INFO |
| Directory structure | Compare folder trees | INFO |
| Component patterns | How UI components are organized | INFO |
| State management | Global state approach | INFO |
| API client | How frontend calls backend | INFO |
| Error boundaries | How errors are caught and displayed | WARNING |
| Testing coverage | Compare test file counts and patterns | WARNING |
| Build pipeline | Compare CI/CD configs | INFO |
| Dependency count | Compare package counts | INFO |
| Bundle size | Compare build output sizes | WARNING |

---

## 6. Logic Flows (Code Mode)

Trace these flows through both codebases and compare the path:

### Auth Flow
1. User submits login form → where does the request go?
2. How are credentials validated?
3. How is the session/token created?
4. How is the session/token stored client-side?
5. How is the session/token verified on subsequent requests?
6. How does logout work?

### CRUD Flow (for a primary entity)
1. How is the entity created? (form → API → DB)
2. How is the entity listed? (DB → API → UI)
3. How is the entity updated? (form → API → DB)
4. How is the entity deleted? (UI → API → DB)
5. What validation exists at each layer?

### Error Flow
1. What happens when the API returns 500?
2. What happens when the network is down?
3. What happens when validation fails?
4. What happens when auth expires?
5. What happens with concurrent edits?

### Data Flow
1. Where is data fetched? (server-side vs client-side)
2. How is data cached?
3. How is data invalidated/refreshed?
4. How does real-time data work (if applicable)?
