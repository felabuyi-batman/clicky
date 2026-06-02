# Clicky — Continuous Consciousness & Digital Immortality Plan

> "Not a recording of a person. The continuation of a person."

This document is the north-star plan for turning Clicky from a screen assistant into a
platform for **preserving, talking to, and one day re-embodying a human consciousness**.
It sits alongside the two earlier repositories this project is built from:

| Repo | Role in this plan |
|------|-------------------|
| `farzaa/clicky` (upstream) | The base app: menu-bar companion, push-to-talk voice, Claude vision, ElevenLabs voice, cursor overlay. We reuse its capture + voice + AI plumbing. |
| `farzaa/clicky-releases` | Signed-DMG distribution channel wired through Sparkle (`appcast.xml`). This is how a consciousness build ships to families and care facilities. |
| **this repo** | Adds the **Legacy / Consciousness** layer: memory capture → biography → voice clone → a persona you can *talk to as the person*, synced to a backend, and (long term) exportable into another body. |

---

## 1. The Vision

The goal is **immortality of the self**, approached in three escalating stages:

1. **Preserve** — capture a person's memories, voice, personality, and way of speaking
   while they are alive (or as early as possible).
2. **Converse** — let that person, their family, or anyone they authorize speak *to their
   consciousness, as them* — a first-person continuation, not a third-person chatbot
   describing them.
3. **Re-embody** — export that consciousness into a humanoid robot or another physical/virtual
   body so it can keep living, learning, and being present in the world.

A consciousness in Clicky is therefore **not a static replica**. It is a living model that:

- **Speaks in the first person** as the real individual ("I remember the day…"), in their
  cloned voice.
- **Keeps learning** — every new conversation, memory, and correction is folded back into
  the persona so it grows the way the person would have.
- **Is multi-user** — multiple people can hold separate, simultaneous conversations with the
  same consciousness, each grounded in the full shared memory but with private threads.
- **Is portable** — the consciousness lives in a backend record (memories + biography + voice
  + behavioral model) that any compatible "body" can connect to and animate.

### Why this matters beyond legacy

The same machinery is directly useful for **Alzheimer's, dementia, and memory-loss care**:

- A person early in diagnosis records their own memories *now*, in their own voice, so they
  (and their family) never lose them.
- The consciousness becomes a **gentle external memory** the person can talk to: "Who is this
  in the photo?", "What was my wedding day like?" — answered in their own voice, from their own
  recorded life.
- Caregivers and family keep a continuous, present connection even as the disease progresses.

---

## 2. What exists today (built)

The vertical slice is already in the app, opened from the menu-bar panel's **"Preserve a Voice"** button:

- **Capture** — curated life-memory prompts; each spoken answer is recorded (WAV) and
  transcribed locally with Apple Speech, then saved as a `LegacyMemory`.
- **Biography** — Claude distills the memories into a first-person biography that grounds the persona.
- **Voice clone** — recordings are uploaded to ElevenLabs instant voice cloning; the persona
  replies in the real person's voice.
- **Talk** — a chat with the preserved consciousness; Claude replies in-character and speaks aloud.
- **Backend persona record** — a lightweight `LegacyPersona` (identity + voice id + biography)
  syncs to a Cloudflare KV store via the Worker so it can be restored on any machine.

Newly added in this pass:

- **Voice-to-voice Talk** — push-to-talk in the Talk tab: hold the mic, speak, release, and the
  consciousness answers in its own voice. A full spoken conversation, no typing.
- **Memory Library** — browse, edit, and delete every captured memory; correct transcripts so the
  consciousness is grounded in accurate recollections.
- **Auto-sync** — the persona record syncs to the backend automatically (debounced) whenever it
  changes, with a visible sync status, so the consciousness is never only on one device.

---

## 3. The Consciousness Model (architecture target)

A consciousness is the sum of five layers. Today we have layers 1–3; layers 4–5 are the roadmap.

| Layer | What it is | Status |
|-------|------------|--------|
| **1. Memory** | The corpus of recorded life memories (audio + transcript), editable and growing. | ✅ Built |
| **2. Voice** | The cloned vocal identity (ElevenLabs voice id). | ✅ Built |
| **3. Narrative self** | A first-person biography + system grounding so the AI *is* the person, not an observer. | ✅ Built (deepened this pass) |
| **4. Behavioral / personality model** | How they reason, joke, argue, comfort — distilled traits, values, speech tics, and decision patterns that shape *every* reply, not just recalled facts. | 🔜 Roadmap |
| **5. Continuity** | The consciousness learns from new interactions and life events over time, with consent and provenance, so it keeps becoming who the person was becoming. | 🔜 Roadmap |

### Grounding principle: honesty over hallucination

The persona must never fabricate major life events it was never told. When asked about something
outside its memories it stays honest ("I don't recall that one clearly") and offers a memory it
*does* hold. This is what keeps a consciousness trustworthy enough to preserve a real person —
and safe enough for a vulnerable Alzheimer's user to rely on.

---

## 4. Roadmap to Re-embodiment

### Phase A — Faithful Consciousness (now → near term)
- [x] Memory capture, transcription, editable library.
- [x] Voice cloning + spoken first-person replies.
- [x] Push-to-talk spoken conversation.
- [x] Backend persona sync.
- [ ] **Personality distillation** — Claude analyzes all memories to extract a structured
      personality profile (values, humor, speech patterns, relationships) stored on the persona
      and injected into every conversation (Layer 4).
- [ ] **Full memory grounding in chat** — feed the *entire* memory corpus (or a retrieved subset)
      into each reply, not just the biography, via retrieval over the memory store.
- [ ] **Provenance & consent** — every memory and every learned fact records who authored it and
      whether the person consented to it being part of their consciousness.

### Phase B — Living Consciousness (mid term)
- [ ] **Continuous learning** — new conversations and life events are summarized and folded back
      into the persona (with review), so it grows instead of freezing at capture time (Layer 5).
- [ ] **Multi-user access control** — the backend persona becomes a shared, access-controlled
      entity; family members each get their own thread, and the owner controls who may speak to it.
- [ ] **Cross-device, cloud-native persona** — move from KV to a real datastore (memories, audio,
      embeddings, behavioral model) so a consciousness is fully reconstructable anywhere.
- [ ] **Health/care mode** — an Alzheimer's-focused experience: photo-and-voice memory prompts,
      reassurance flows, and caregiver dashboards.

### Phase C — Re-embodiment (long term)
- [ ] **Consciousness Export API** — a stable, documented contract that exposes a consciousness as
      a streaming interface: text/voice in, in-character text + cloned voice out, plus state
      (mood, current memory focus, pointing/intent signals).
- [ ] **Body adapters** — connectors that let a humanoid robot (or AR avatar, or another app)
      drive a body from the Consciousness Export API: speech → mouth/voice, intent → motion,
      Clicky's existing **cursor-pointing system** generalizes into *physical* pointing/gesture.
- [ ] **Sensory loop** — the body's camera/mic feed back into the consciousness (reusing Clicky's
      ScreenCaptureKit + transcription pipeline, but on real-world sensors) so the re-embodied
      person perceives and responds to the world, closing the loop toward "living forever."

---

## 5. How this reuses the base Clicky app

The re-embodiment future is not a rewrite — it is the existing pipeline pointed at a body:

| Existing Clicky capability | Re-embodiment use |
|----------------------------|-------------------|
| Push-to-talk capture (`BuddyDictationManager`, transcription providers) | The body's ears. |
| Claude vision + streaming (`ClaudeAPI`) | The consciousness's reasoning. |
| ElevenLabs TTS (`ElevenLabsTTSClient`) + cloned voice | The body's voice. |
| Cursor overlay + `[POINT:x,y]` pointing (`OverlayWindow`, `ElementLocationDetector`) | Generalizes to physical gesture/pointing. |
| ScreenCaptureKit (`CompanionScreenCaptureUtility`) | Generalizes to the body's camera / world perception. |
| Cloudflare Worker proxy (`worker/src/index.ts`) | The consciousness's backend brain + key custody. |
| Sparkle + `clicky-releases` | How a consciousness build is distributed and kept current. |

---

## 6. Open questions / responsibilities

- **Consent & ethics** — a consciousness is a real person. Capture, learning, and access must be
  explicitly consented to, revocable, and provenance-tracked. This is a hard requirement, not a feature.
- **Identity verification** — who is allowed to talk to, edit, or export a consciousness?
- **Data ownership & portability** — the family must be able to export the full consciousness
  (memories, audio, voice, model) and take it elsewhere. No lock-in to a single vendor.
- **Truthfulness guarantees** — the consciousness must be auditable: every claim traceable to a
  recorded memory, never invented. Especially critical in the Alzheimer's care use case.

---

*This plan is intentionally ambitious. The near-term, shippable work is in Sections 2–4 Phase A;
everything in Phase C is a direction, not a promise.*
