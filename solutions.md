# solutions.md

## RES-101 — Search shows results for the wrong query

**Root cause:** `_search()` fired on every keystroke with no delay and no way to cancel old requests. The API is intentionally slower for short broad queries like "s" (~1.2s) than specific ones like "sushi" (~0.2s). So typing "sushi" sends 5 requests — "sushi" returns first and shows correct results, then "s" returns last and overwrites them.

**Why this fix is the right one:** Added a 300ms debounce time so only the final query is sent after the use pauses for a moment. Also added a generation counter so each search gets a ticket number, and when results come back we check if the number is still current. If a newer search starts, the stale results will be thrown away.

- _Alternative considered and rejected:_ My first thought after seeing the bug was using the debounce timer only. But when I discussed with the AI, I found that we really need both debounce and generation counter because if a user types and pauses (triggering a slow search), and then types again (triggering a fast search), the slow search could still arrive late and overwrite the correct results.

**Edge cases:** Clearing the text field resets immediately (no debounce). The debounce timer is cancelled in `onClose()` so it can't fire after the search screen is closed.

---

## AI Usage Log

**Tool used:** Antigravity IDE (Claude) for codebase analysis and understanding, root-cause identification, code fixes, and documentation.

**How I used it:** I had the AI analyze the entire codebase first to map out the architecture roughly, skim through the code and identify root causes for all bugs before writing any code. For each fix, I reviewed every line the AI generated and tested it myself. I commented out parts of the fix (eg. generation counter for search) to verify it was actually necessary by reproducing the bug without it.

**Example 1 — wrong/misleading AI suggestion:**
_(To be filled with a real example as we `work through more bugs)_

**Example 2 — wrong/misleading AI suggestion:**
_(To be filled with a real example as we work through more bugs)_

---

## Design Questions

**Q1:** _(To be answered)_

**Q2:** _(To be answered)_

**Q3:** _(To be answered)_

---

## Time Spent

| Phase               | Time  |
| ------------------- | ----- |
| Setup & environment | ~1 hr |
| Codebase analysis   | ~2 hr |
| Bug fixes           |       |
| Features            |       |
| Documentation       |       |
| **Total**           |       |

**What I'd do with one more day:** _(To be filled at the end)_
