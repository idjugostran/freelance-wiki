---
name: freelance-wiki-context
description: "Grounds answers about Upwork or Fiverr in the Freelance wiki (40 ingested videos). Trigger: 'Upwork'/'Fiverr' (or the common misspelling 'Fiver') anywhere in the conversation, any case/language — including Russian transliterations апворк/апарк and файвер/фивер, any declension."
platforms: [macos, linux]
metadata: {"hermes":{"tags":["upwork","fiverr","freelance","wiki","knowledge-base"],"category":"knowledge-base","requires_tools":["python3"],"related_skills":["tokovinin-kb-context"]}}
---

# Freelance Wiki (Upwork/Fiverr) Context

## When to use

Trigger whenever **Upwork** or **Fiverr** is mentioned anywhere in the user's
message, in any of these forms (not an exhaustive list — match the intent,
not just these exact strings):

- English: `Upwork`, `upwork`, `Fiverr`, `fiverr`, `Fiver` (a very common
  misspelling of Fiverr — treat it the same as `Fiverr`)
- Russian, any case/declension: `апворк` / `Апворк` (апворка, апворке,
  апворком...), `апарк` (a colloquial/ASR-garbled spelling of the same word
  seen across the source videos), `файвер` / `Файвер` (файвера, файверу,
  файвером...), `фивер` / `Фивер`

Not limited to explicit questions ("расскажи про регистрацию на Fiverr") —
any mention at all is enough, including passing references ("я зарегался на
апворке вчера", "думаю податься на файвер").

This is a **grounding skill**, not a whole-file-attachment one: unlike
`tokovinin-kb-context` (a single ~2k-token file, cheap to attach whole every
time), the Freelance wiki is ~65 pages / ~200k tokens. Dumping all of it into
context on every mention would be wasteful and often irrelevant. Instead,
read *just* the pages relevant to what's being asked, the same way the
`wiki-query` skill works.

## What to do

This skill lives inside the wiki's own project (`/Users/idjugostran/Projects/Freelance`),
next to `SCHEMA.md`, `wiki/pages/*.md` and `wiki/overview.md` — a wiki built
with the `wiki-skills` Claude Code plugin. Its `link_style` is `markdown`:
cross-references and citations look like `[[slug](pages/slug.md)]`.

1. **Regenerate and read the index.**
   ```
   cd /Users/idjugostran/Projects/Freelance && python3 bin/generate-index.py
   ```
   Then read `wiki/index.md` in full — it's grouped by category (Sources /
   Entities / Concepts) with a one-line summary per page. Use it to identify
   which pages are actually relevant to the mention/question. Don't answer
   from general knowledge about Upwork/Fiverr — the wiki is ground truth
   here, and it frequently disagrees with generic platform knowledge on
   specifics (commission rates, cold-start timing, ban risks, etc.) or
   documents things (e.g. a specific fraud pattern, a specific fee) generic
   knowledge wouldn't have at all.

2. **Read the relevant pages in full**, not summaries or greps. For a broad
   mention with no specific question ("апворк топ"), start from the entity
   page (`wiki/pages/upwork.md` or `wiki/pages/fiverr.md`) — both are dense
   synthesis pages that link out to everything else. For a specific
   question, go straight to the most relevant Concept/Source page(s) from
   the index. Follow one level of `[[slug](pages/slug.md)]` cross-references
   if they point somewhere clearly relevant.

3. **Synthesize an answer grounded in what you read:**
   - Cite every claim with the wiki's cross-reference for the page it came
     from: `[[slug](pages/slug.md)]`.
   - Where a footnote in the cited page has a timestamp (`[HH:MM:SS]` or
     `[MM:SS]`) and the underlying Source page's `**Source:**` line has a
     YouTube URL, prefer rendering that as a clickable timestamp link
     instead of a bare citation — same convention as `tokovinin-kb-context`:
     convert the timestamp to seconds and link as
     `[HH:MM:SS](https://youtu.be/VIDEO_ID?t=SECONDS)`. Telegram (and other
     surfaces Hermes renders markdown for) turns this into a clickable link
     that jumps straight to that moment. Only do this when you've actually
     opened the Source page and confirmed the video ID — never guess it.
   - Explicitly surface disagreements between sources rather than picking
     one silently — the wiki deliberately preserves unresolved tensions
     (e.g. VPN-ban-risk vs. long-term antidetect-browser safety, Upwork's
     commission 10% vs ~20%, Fiverr's cold-start timing) in page bodies and
     in `wiki/overview.md`'s Open Questions section. If the topic touches
     one of these, say so instead of quietly picking a side.
   - If the wiki has no page covering what was asked, say so plainly
     ("в базе знаний вики пока нет ничего про X") rather than falling back
     to general knowledge silently.

4. **Do not write to the wiki from this skill.** This is read-only context
   grounding, same as `tokovinin-kb-context`'s relationship to
   `tokovinin-video-flow`. Adding a new video/source to the wiki is a
   separate, manual workflow (`wiki-ingest`, not covered by this skill) —
   if the user asks to add something new, say that's a separate step rather
   than attempting it here.

## Notes

- **Targeted read, not whole-file attach** — see "When to use" above for
  why. If the wiki ever shrinks to Tokovinin-KB size this could be
  simplified, but at ~200k tokens across 65 pages that's not close.
- **Not yet registered with Hermes.** This folder lives at
  `/Users/idjugostran/Projects/Freelance/skill/freelance-wiki-context` —
  Hermes only scans directories listed in `skills.external_dirs` in
  `~/.hermes/config.yaml`, which currently only points at
  `/Users/idjugostran/Tokovinin/skill` (the Tokovinin project's own skills).
  A second `external_dirs` entry for this path (or an equivalent install
  script, mirroring `tokovinin-video-flow/scripts/setup.sh`'s config-patch
  step) is a separate, not-yet-built install flow — until that exists,
  Hermes will not pick this skill up on its own.
