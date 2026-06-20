import QtQuick

/*!
    ModelCapabilityProbe.qml — capability detection by asking the model
    itself, not by matching the model name against a hardcoded family
    table.

    Tries in order:
      1. Ollama native API: POST {endpoint}/api/show {"name": "..."}
         returns the canonical `capabilities` array (e.g. ["completion",
         "tools"]) plus `details.parameter_size` and
         `model_info.<family>.context_length`. This is the highest-fidelity
         probe because it tells us *the model itself* whether it can use
         tools, not what we *guess* from its name.
      2. OpenAI-compatible `/v1/models/{model}` (works for OpenAI,
         Anthropic-via-proxy, Ollama's /v1 surface, OpenRouter, Together,
         LM Studio, etc.). Returns basic metadata; not as rich as Ollama
         native but confirms existence.
      3. Heuristic fallback — family-name lookup in ApiStrategy. ONLY
         used when both probes fail or are unsupported. Documented as a
         fallback so future maintainers don't add more hardcoded rules
         here.

    Results are cached by `endpoint|model` key. The cache is populated
    asynchronously (fire-and-forget) so the first chat request isn't
    blocked on a probe. Subsequent requests hit the cache.

    The probe also exposes `recordOutcome(modelObj, success, usedTools,
    hadReasoning)` so Ai.qml can refine the cached record based on
    empirical observations — if the model *did* return a tool_call
    when we asked for one, we mark it tools-capable; if it emitted a
     reasoning_content field, we mark it reasoning-capable. This is
    the long-term path away from hardcoded heuristics entirely.
*/
QtObject {
    id: root

    // Cache shape:
    //   { "<endpoint>|<model>": <capabilities>, ... }
    // capabilities shape:
    //   {
    //     supportsTools: bool,
    //     supportsVision: bool,
    //     supportsThinking: bool,
    //     supportsReasoningField: bool,   // reasoning_content in a separate field
    //     supportsInlineThinking: bool,   //  in the content stream
    //     supportsToolChoiceRequired: bool,
    //     contextLength: int,
    //     defaultTemperature: real,
    //     parameterSize: string,          // "7B", "27B", ...
    //     source: string,                 // "ollama" | "openai" | "heuristic"
    //     probedAt: int                   // unix ms
    //   }
    property var cache: ({})

    // Network probing process — kept here so the cache can be primed
    // in the background without an external component managing it.
    property var _inflight: ({})

    signal capabilityUpdated(var modelObj, var capabilities)

    function _cacheKey(modelObj) {
        return ((modelObj && modelObj.endpoint) || "") + "|"
            + ((modelObj && modelObj.model) || "");
    }

    // Synchronous lookup — returns the cached value or null. The
    // caller (Ai.qml.makeRequest) treats null as "no probe yet" and
    // falls back to the strategy-level family heuristic for THIS
    // request, then triggers a background probe so the NEXT request
    // hits the cache.
    function cachedFor(modelObj) {
        let k = _cacheKey(modelObj);
        return cache[k] || null;
    }

    // Force a probe. Idempotent: if a probe is already in flight for
    // this model we don't fire a second one. Returns the cached value
    // immediately if it exists.
    function probe(modelObj, apiKey) {
        let k = _cacheKey(modelObj);
        if (cache[k]) {
            capabilityUpdated(modelObj, cache[k]);
            return cache[k];
        }
        if (_inflight[k]) return null;
        if (!modelObj || !modelObj.model || !modelObj.endpoint) return null;
        _inflight[k] = true;
        if (_isOllama(modelObj))
            _probeOllama(modelObj, apiKey, k);
        else
            _probeOpenAI(modelObj, apiKey, k);
        return null;
    }

    // Record what actually happened on the last request — used to
    // refine the cached record without re-probing. For example, a
    // heuristic-flagged-as-tools-capable model that never returned
    // a tool_call should be downgraded. And a model that DID return
    // a reasoning_content field when none was expected should be
    // upgraded.
    //
    // `usedTools`      — true iff the model returned a tool_call entry.
    // `hadReasoning`   — true iff the model emitted reasoning_content.
    // `hadInlineThink` — true iff the response content matched the
    //                    inline-think-tag regex after the strategy's
    //                    normalisation pass.
    // `wasEmpty`       — true iff the model returned no content and no
    //                    tool_call (the gemma2 / qwen3 empty-response
    //                    symptom). Helps us learn which families need
    //                    the nudge layer.
    function recordOutcome(modelObj, usedTools, hadReasoning,
            hadInlineThink, wasEmpty, toolsRequested) {
        let k = _cacheKey(modelObj);
        let caps = cache[k];
        if (!caps) return;
        let updated = Object.assign({}, caps);
        if (usedTools && !caps.supportsTools) {
            updated.supportsTools = true;
        }
        if (hadReasoning && !caps.supportsReasoningField) {
            updated.supportsReasoningField = true;
        }
        if (hadInlineThink && !caps.supportsInlineThinking) {
            updated.supportsInlineThinking = true;
            updated.supportsThinking = true;
        }
        // Empty response = the heuristic/strategy is misconfigured
        // for this model. Drop supportsToolChoiceRequired to false
        // so the nudge layer uses a textual prompt instead of the
        // provider's required-mode (which the model ignored).
        if (wasEmpty && caps.supportsToolChoiceRequired) {
            updated.supportsToolChoiceRequired = false;
        }
        // The big one: if we ASKED for tools and the model returned
        // empty, the model can't reliably use the tools schema. This
        // is the Gemma2:2b symptom — it claims `tools` capability but
        // returns empty the moment the request body includes the
        // tools field. Downgrade to text-only mode and let the
        // text-intent detector (which handles plain-text `tool(...)`
        // calls many small models emit) take over.
        if (wasEmpty && toolsRequested && caps.supportsTools) {
            console.warn("[ModelCapabilityProbe] " + (modelObj.model || "")
                + " returned empty with tools in the request — "
                + "downgrading to text-only mode (will retry without "
                + "tools on the next turn).");
            updated.supportsTools = false;
            updated.forceTextOnly = true;
        }
        updated.probedAt = Date.now();
        cache[k] = updated;
        capabilityUpdated(modelObj, updated);
    }

    // ────────────────────────────────────────────────────────────────
    // URL classification
    // ────────────────────────────────────────────────────────────────

    function _isOllama(modelObj) {
        let ep = (modelObj && modelObj.endpoint) || "";
        let lower = ep.toLowerCase();
        if (lower.indexOf("ollama.com") >= 0) return true;
        if (lower.indexOf("localhost") >= 0
                || lower.indexOf("127.0.0.1") >= 0
                || lower.indexOf("0.0.0.0") >= 0
                || lower.indexOf("[::1]") >= 0
                || lower.indexOf("[::]") >= 0
                || lower.indexOf(":11434") >= 0) {
            // Loopback or Ollama's default port. Could be Ollama native
            // (/api/chat), Ollama OpenAI-compat (/v1), LM Studio
            // (also loopback), or llama.cpp's server. We try Ollama
            // native first; on failure the OpenAI probe path takes
            // over via the `/v1/models/{model}` probe — Ollama exposes
            // BOTH endpoints so this works either way.
            return true;
        }
        return false;
    }

    // ────────────────────────────────────────────────────────────────
    // Ollama native probe — POST {endpoint}/api/show
    // ────────────────────────────────────────────────────────────────

    function _probeOllama(modelObj, apiKey, key) {
        let base = _ollamaApiRoot(modelObj.endpoint);
        let url = base + "/show";
        let body = JSON.stringify({ name: modelObj.model });
        let req = new XMLHttpRequest();
        // Ollama's /api/show is unauthenticated on localhost. For
        // Ollama Cloud (ollama.com) the bearer header from KeyStore
        // is sent automatically when apiKey is non-empty.
        req.open("POST", url, true);
        req.setRequestHeader("Content-Type", "application/json");
        if (apiKey) req.setRequestHeader("Authorization", "Bearer " + apiKey);
        req.timeout = 5000;
        req.onreadystatechange = function() {
            if (req.readyState !== XMLHttpRequest.DONE) return;
            delete _inflight[key];
            if (req.status < 200 || req.status >= 300) {
                // Fall back to OpenAI-compatible probe — Ollama exposes
                // /v1/models/{model} too. If that also fails we leave
                // the cache empty so the strategy falls through to
                // the heuristic.
                _probeOpenAI(modelObj, apiKey, key);
                return;
            }
            try {
                let data = JSON.parse(req.responseText);
                _recordOllamaResult(modelObj, data, key);
            } catch (e) {
                _probeOpenAI(modelObj, apiKey, key);
            }
        };
        try { req.send(body); }
        catch (e) {
            delete _inflight[key];
            _probeOpenAI(modelObj, apiKey, key);
        }
    }

    function _ollamaApiRoot(endpoint) {
        let url = (endpoint || "").trim().rstrip("/");
        // Strip OpenAI-compat suffix if the strategy is using /v1.
        // Order matters: handle compound /v1/<action> suffixes before
        // bare /v1 because both share the `/v1` suffix.
        for (let s of ["/v1/chat/completions", "/v1/responses",
                "/v1/messages", "/v1/models"]) {
            if (url.endsWith(s)) {
                url = url.slice(0, -s.length).rstrip("/");
                break;
            }
        }
        if (url.endsWith("/v1"))
            url = url.slice(0, -3).rstrip("/");
        if (url === "" || url.endsWith("/api")) {
            return url;
        }
        if (url.indexOf("/api/") >= 0) return url;
        return url + "/api";
    }

    function _recordOllamaResult(modelObj, data, key) {
        let caps = (data && data.capabilities) || [];
        let tools = caps.indexOf("tools") >= 0;
        // Ollama exposes the model's context window in
        // model_info.<family>.context_length. Try a few common family
        // keys; fall back to a generous default.
        let ctx = 0;
        let mi = (data && data.model_info) || {};
        for (let k in mi) {
            if (k.indexOf("context_length") >= 0) {
                let n = parseInt(mi[k]);
                if (n > 0) { ctx = n; break; }
            }
        }
        // Parameter size comes back as e.g. "7B" or "2.5B" — use it
        // as a tier hint for the strategy's prompt-budget heuristic.
        let paramSize = (data && data.details && data.details.parameter_size) || "";
        let paramBillions = _parseParamBillions(paramSize);

        let family = (data && data.details && data.details.family) || "";
        let familyLower = String(family).toLowerCase();
        // Inline thinking is a model-level trait for the qwen3 / gemma
        // / deepseek-r1 families. We derive it from the family rather
        // than the capability list because Ollama doesn't surface
        // thinking as a capability flag.
        let inlineThink = (familyLower.indexOf("qwen") >= 0
                && (familyLower.indexOf("3") >= 0 || familyLower.indexOf("qwq") >= 0))
            || familyLower.indexOf("gemma") >= 0
            || familyLower.indexOf("deepseek") >= 0
            || familyLower.indexOf("minimax") >= 0;

        // Tiny models (≤2B parameters) reliably fail to use tools.
        // Gemma2:2b is the canonical example: it lists `tools` in
        // /api/show but returns empty completions the moment it sees
        // a tools field with structured schemas. Force-disable tools
        // for these and let Ai.qml fall back to text-only intent
        // detection (which still works for tiny models — they often
        // emit tool calls as plain text in fenced blocks).
        let tooSmallForTools = paramBillions > 0 && paramBillions <= 2.0;
        if (tooSmallForTools && tools) {
            console.warn("[ModelCapabilityProbe] " + (modelObj.model || "")
                + " reports tools capability but is only "
                + (paramBillions.toFixed(1)) + "B params — "
                + "disabling tools; falling back to text-only mode.");
            tools = false;
        }

        let rec = {
            supportsTools: tools,
            supportsVision: caps.indexOf("vision") >= 0,
            supportsThinking: inlineThink,
            supportsReasoningField: inlineThink
                && familyLower.indexOf("deepseek") >= 0,
            supportsInlineThinking: inlineThink,
            // Local model families generally don't honour
            // tool_choice:"required"; the only safe path is the
            // textual nudge. Reasoning models (o1/o3/gpt-5) ARE
            // server-side though, so set this to true at the
            // OpenAI-compatible layer (see _probeOpenAI).
            supportsToolChoiceRequired: false,
            contextLength: ctx,
            defaultTemperature: 0.7,
            parameterSize: paramSize,
            // `forceTextOnly` is the explicit signal to Ai.qml: tools
            // are off not because of a probe miss, but because the
            // model is too small to use them. The sidebar surfaces
            // this as a "Text-only mode (model too small for tools)"
            // status pill so the user understands why agent-mode
            // commands run without tool calls.
            forceTextOnly: tooSmallForTools,
            source: "ollama",
            probedAt: Date.now()
        };
        cache[key] = rec;
        capabilityUpdated(modelObj, rec);
    }

    // Parse Ollama's parameter_size string ("2B", "7B", "27B",
    // "500M", "1.5B") into a float in billions. Returns 0 when the
    // string isn't a recognised size — callers treat 0 as "unknown"
    // so we don't accidentally force-disable tools on a server we
    // couldn't measure.
    function _parseParamBillions(sizeStr) {
        if (!sizeStr) return 0;
        let s = String(sizeStr).trim().toUpperCase();
        let m = s.match(/^(\d+(?:\.\d+)?)\s*([BMK]?)$/);
        if (!m) return 0;
        let n = parseFloat(m[1]);
        let unit = m[2];
        if (unit === "M") return n / 1000.0;
        if (unit === "K") return n / 1000000.0;
        return n;  // "B" or no unit
    }

    // ────────────────────────────────────────────────────────────────
    // OpenAI-compatible /v1/models/{model} probe
    // ────────────────────────────────────────────────────────────────

    function _probeOpenAI(modelObj, apiKey, key) {
        let base = _openAIBase(modelObj.endpoint);
        if (!base) { delete _inflight[key]; return; }
        let url = base + "/models/" + encodeURIComponent(modelObj.model);
        let req = new XMLHttpRequest();
        req.open("GET", url, true);
        if (apiKey) req.setRequestHeader("Authorization", "Bearer " + apiKey);
        req.timeout = 5000;
        req.onreadystatechange = function() {
            if (req.readyState !== XMLHttpRequest.DONE) return;
            delete _inflight[key];
            if (req.status < 200 || req.status >= 300) return;
            try {
                let data = JSON.parse(req.responseText);
                _recordOpenAIResult(modelObj, data, key);
            } catch (e) { /* ignore — heuristic will take over */ }
        };
        try { req.send(); }
        catch (e) { delete _inflight[key]; }
    }

    function _openAIBase(endpoint) {
        let url = (endpoint || "").trim().rstrip("/");
        // Check compound suffixes first (/v1/messages, /v1/responses)
        // so a URL ending in /v1/messages strips both /v1 and /messages
        // and lands at the base. Order matters — longest match wins.
        for (let s of ["/v1/chat/completions", "/v1/messages",
                "/v1/responses", "/chat/completions",
                "/completions", "/models"]) {
            if (url.endsWith(s)) {
                url = url.slice(0, -s.length).rstrip("/");
                break;
            }
        }
        if (!url.endsWith("/v1")) url = url + "/v1";
        return url;
    }

    function _recordOpenAIResult(modelObj, data, key) {
        // /v1/models/{model} doesn't expose a "supports tools" field,
        // so we don't pretend to know. We DO know: the model exists
        // and is reachable. The strategy's tool_choice layer still
        // gets to try; if the model returns empty on tool_choice:
        // required, the recordOutcome hook downgrades us.
        let rec = {
            supportsTools: true,
            supportsVision: true,
            supportsThinking: false,
            supportsReasoningField: false,
            supportsInlineThinking: false,
            supportsToolChoiceRequired: true,
            contextLength: 0,
            defaultTemperature: 0.7,
            parameterSize: "",
            source: "openai",
            probedAt: Date.now()
        };
        cache[key] = rec;
        capabilityUpdated(modelObj, rec);
    }

    // ────────────────────────────────────────────────────────────────
    // Manual cache injection (for tests / pre-seeding from settings)
    // ────────────────────────────────────────────────────────────────

    function seed(modelObj, capabilities) {
        let k = _cacheKey(modelObj);
        cache[k] = capabilities;
        capabilityUpdated(modelObj, capabilities);
    }
}
