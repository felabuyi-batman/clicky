/**
 * Clicky Proxy Worker
 *
 * Proxies requests to Claude and ElevenLabs APIs so the app never
 * ships with raw API keys. Keys are stored as Cloudflare secrets.
 *
 * Routes:
 *   POST /chat         → Anthropic Messages API (streaming)
 *   POST /tts          → ElevenLabs TTS API (optional per-request voice_id)
 *   GET  /transcribe-token → AssemblyAI short-lived streaming token
 *   POST /voice-clone  → ElevenLabs instant voice cloning (multipart audio in)
 *   PUT  /persona/:id  → store a legacy persona JSON in KV
 *   GET  /persona/:id  → fetch a stored legacy persona JSON from KV
 */

interface Env {
  ANTHROPIC_API_KEY: string;
  ELEVENLABS_API_KEY: string;
  ELEVENLABS_VOICE_ID: string;
  ASSEMBLYAI_API_KEY: string;
  // KV namespace holding legacy persona JSON, keyed by persona id.
  LEGACY_PERSONA_STORE: KVNamespace;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    try {
      // Persona sync is keyed by id in the path and supports GET + PUT, so it
      // is matched before the POST-only routes below.
      if (url.pathname.startsWith("/persona/")) {
        return await handlePersonaSync(request, env, url);
      }

      // The transcribe token is fetched with GET.
      if (url.pathname === "/transcribe-token" && request.method === "GET") {
        return await handleTranscribeToken(env);
      }

      if (request.method !== "POST") {
        return new Response("Method not allowed", { status: 405 });
      }

      if (url.pathname === "/chat") {
        return await handleChat(request, env);
      }

      if (url.pathname === "/tts") {
        return await handleTTS(request, env);
      }

      if (url.pathname === "/voice-clone") {
        return await handleVoiceClone(request, env);
      }
    } catch (error) {
      console.error(`[${url.pathname}] Unhandled error:`, error);
      return new Response(
        JSON.stringify({ error: String(error) }),
        { status: 500, headers: { "content-type": "application/json" } }
      );
    }

    return new Response("Not found", { status: 404 });
  },
};

async function handleChat(request: Request, env: Env): Promise<Response> {
  const body = await request.text();

  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": env.ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body,
  });

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/chat] Anthropic API error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(response.body, {
    status: response.status,
    headers: {
      "content-type": response.headers.get("content-type") || "text/event-stream",
      "cache-control": "no-cache",
    },
  });
}

async function handleTranscribeToken(env: Env): Promise<Response> {
  const response = await fetch(
    "https://streaming.assemblyai.com/v3/token?expires_in_seconds=480",
    {
      method: "GET",
      headers: {
        authorization: env.ASSEMBLYAI_API_KEY,
      },
    }
  );

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/transcribe-token] AssemblyAI token error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  const data = await response.text();
  return new Response(data, {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}

async function handleTTS(request: Request, env: Env): Promise<Response> {
  const body = await request.text();

  // Allow the app to request a specific cloned voice per call. When the body
  // includes a non-empty "voice_id", use it; otherwise fall back to the
  // default voice configured on the Worker. The voice_id is stripped before
  // forwarding because ElevenLabs takes the voice in the URL, not the body.
  let voiceId = env.ELEVENLABS_VOICE_ID;
  let upstreamBody = body;
  try {
    const parsedBody = JSON.parse(body) as Record<string, unknown>;
    if (typeof parsedBody.voice_id === "string" && parsedBody.voice_id.length > 0) {
      voiceId = parsedBody.voice_id;
    }
    delete parsedBody.voice_id;
    upstreamBody = JSON.stringify(parsedBody);
  } catch {
    // Body wasn't JSON we could parse; forward it untouched with the default voice.
  }

  const response = await fetch(
    `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`,
    {
      method: "POST",
      headers: {
        "xi-api-key": env.ELEVENLABS_API_KEY,
        "content-type": "application/json",
        accept: "audio/mpeg",
      },
      body: upstreamBody,
    }
  );

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/tts] ElevenLabs API error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(response.body, {
    status: response.status,
    headers: {
      "content-type": response.headers.get("content-type") || "audio/mpeg",
    },
  });
}

/**
 * Instant voice cloning. The app uploads the user's recorded memory audio as
 * multipart/form-data (a "name" field plus one or more "files"). We forward it
 * to ElevenLabs' add-voice endpoint with the API key and return the new
 * voice_id, which the app stores on the persona for spoken replies.
 */
async function handleVoiceClone(request: Request, env: Env): Promise<Response> {
  const contentType = request.headers.get("content-type") || "";
  if (!contentType.includes("multipart/form-data")) {
    return new Response(
      JSON.stringify({ error: "Expected multipart/form-data with audio files" }),
      { status: 400, headers: { "content-type": "application/json" } }
    );
  }

  // Forward the multipart body through unchanged; ElevenLabs parses the same
  // form fields the app sent. The content-type (with its multipart boundary)
  // must be preserved exactly.
  const response = await fetch("https://api.elevenlabs.io/v1/voices/add", {
    method: "POST",
    headers: {
      "xi-api-key": env.ELEVENLABS_API_KEY,
      "content-type": contentType,
    },
    body: request.body,
  });

  const responseBody = await response.text();
  if (!response.ok) {
    console.error(`[/voice-clone] ElevenLabs add-voice error ${response.status}: ${responseBody}`);
  }
  return new Response(responseBody, {
    status: response.status,
    headers: { "content-type": "application/json" },
  });
}

/**
 * Stores and retrieves a legacy persona JSON in KV so the user's "digital you"
 * survives reinstalls and can be shared with family. The persona id is the
 * last path segment (PUT to save, GET to load).
 */
async function handlePersonaSync(request: Request, env: Env, url: URL): Promise<Response> {
  const personaID = url.pathname.replace("/persona/", "").trim();
  if (personaID.length === 0) {
    return new Response(
      JSON.stringify({ error: "Missing persona id" }),
      { status: 400, headers: { "content-type": "application/json" } }
    );
  }

  const storageKey = `persona:${personaID}`;

  if (request.method === "PUT") {
    const personaJSON = await request.text();
    await env.LEGACY_PERSONA_STORE.put(storageKey, personaJSON);
    return new Response(
      JSON.stringify({ ok: true, id: personaID }),
      { status: 200, headers: { "content-type": "application/json" } }
    );
  }

  if (request.method === "GET") {
    const storedPersonaJSON = await env.LEGACY_PERSONA_STORE.get(storageKey);
    if (storedPersonaJSON === null) {
      return new Response(
        JSON.stringify({ error: "Persona not found" }),
        { status: 404, headers: { "content-type": "application/json" } }
      );
    }
    return new Response(storedPersonaJSON, {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response("Method not allowed", { status: 405 });
}
