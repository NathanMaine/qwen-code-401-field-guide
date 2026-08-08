# Qwen Code 401 — A Field Guide

<p align="center">
  <img src="qwen_help.jpeg" alt="One valid key, three doors — two flash 401, one opens" width="100%">
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT license"></a>
  <img src="https://img.shields.io/badge/keys%20printed-zero-blue" alt="zero keys printed">
  <img src="https://img.shields.io/badge/status-battle--tested-orange" alt="battle-tested">
</p>

> **TL;DR**
> `401 invalid access token or token expired` from an `sk-sp-` key that the console
> says is valid = **wrong endpoint, not dead key.** Find the one door your key type
> opens ([§1](#s1)), prove it with a real
> completion — never `/models` ([§2](#s2)) — and
> point every `baseUrl` at it ([§4](#s4)).

**The error:**

```text
Internal error: 401 invalid access token or token expired
```

**The trap:** this message makes you think your API key is dead — but the provider
console says the key is valid, regenerating it doesn't help, and reinstalling the
extension doesn't help either. That's because for `sk-sp-` keys, **this 401 usually
means the key is being sent to the wrong endpoint, not that it expired.** The
wrong-door response is byte-identical to the expired-key response.

This guide is the result of debugging that exact loop end-to-end: the key taxonomy
nobody explains, an endpoint matrix, a diagnosis method that can't be fooled,
working config templates, and an audit script for comparing machines.

| Jump to | |
| --- | --- |
| [§1 The root cause](#s1) | one prefix, three products |
| [§2 The `/models` trap](#s2) | the sanity check that lies |
| [§3 Diagnosis](#s3) | four steps, can't be fooled |
| [§4 The fix](#s4) | working config + template |
| [§5 Gotchas](#s5) | red herrings & caps |
| [§6 Audit script](#s6) | compare machines, zero keys printed |

---

<a id="s1"></a>

## 1. 🗝️ The root cause: one prefix, three products

Alibaba Cloud's Qwen ecosystem has (at least) three different credential types
that all get called "the API key":

| Key type | Looks like | Works ONLY against |
| --- | --- | --- |
| **Standard Model Studio** | `sk-` + 32 hex (~35 chars) | General endpoints: `dashscope.aliyuncs.com` (China) / `dashscope-intl…` / `dashscope-us…` `/compatible-mode/v1` |
| **Coding Plan** (individual, weekly quota) | `sk-sp-…` (long, may contain dots) | `coding.dashscope.aliyuncs.com/v1` (China) / `coding-intl.dashscope.aliyuncs.com/v1` (global) |
| **Token Plan** (teams, usage-billed) | `sk-sp-…` (long, may contain dots) | `token-plan.<region>.maas.aliyuncs.com/compatible-mode/v1` (e.g. `ap-southeast-1`, `cn-beijing`) |

Three things make this brutal to debug:

1. **Coding Plan and Token Plan keys share the `sk-sp-` prefix** but are different
   products with different exclusive endpoints. You cannot tell them apart by
   looking at the key.
2. **Every wrong pairing returns the same 401** — "invalid access token or token
   expired" — whether the key is genuinely dead, from the wrong product, or from
   the wrong region.
3. Keys are also **region-scoped**: a China-console key fails on international
   endpoints and vice versa, again with the same message.

The official error-code page confirms the plan-key rule ("dedicated API keys …
must not be mixed with the general API Key/Base URL"):
<https://www.alibabacloud.com/help/en/model-studio/error-code#apikey-error>

<a id="s2"></a>

## 2. 🕳️ The `/models` trap — do not trust it

Some of the plan endpoints' `/v1/models` routes **accept any Bearer token**,
including complete garbage. A `200` from `/models` does NOT mean your key is
valid there.

**Only `/chat/completions` validates the key.** Always test with a real, tiny
completion — and run a garbage-key control against the same route so you know
whether that route checks auth at all:

```bash
# real test — a 401 here is meaningful; a 200 means the pairing works
curl -s https://<candidate-endpoint>/chat/completions \
  -H "Authorization: Bearer $YOUR_KEY" -H "Content-Type: application/json" \
  -d '{"model":"<a-model>","max_tokens":8,"messages":[{"role":"user","content":"Say OK"}]}'

# control — if a garbage key gets a 200 on some route, that route proves nothing
```

💡 Bonus tell: a **404 `model_not_found`** is *good news* — the endpoint
authenticated your key and only rejected the model name. You've found the right
door; now list what it serves.

<a id="s3"></a>

## 3. 🩺 Diagnosis in four steps

1. **Shape-check the key** (without printing it): length and prefix.
   ~35 chars `sk-` + hex → Standard. Long `sk-sp-` → one of the two plans.
2. **Probe each candidate endpoint with a real completion** ([§2](#s2)).
   Wrong doors 401; the right door returns 200 — or 404 `model_not_found`, which
   still means the auth succeeded.
3. **List the models the right door serves** (`GET /v1/models` on the door that
   validated) and use exactly those IDs. Note: unlisted models sometimes still
   work — the listing can lag the entitlement.
4. **Only if every door rejects it** is the key actually dead — regenerate it in
   the console then. Remember regeneration invalidates the old key on every
   machine that has a copy.

<a id="s4"></a>

## 4. 🔧 The fix — Qwen Code configuration that works

`~/.qwen/settings.json` (macOS/Linux; `C:\Users\<you>\.qwen\` on Windows) — see
[`settings.template.json`](settings.template.json) for the full file:

- `env`: store the key under a name that says what it is (e.g.
  `TOKEN_PLAN_API_KEY`) — calling a plan key `DASHSCOPE_API_KEY` is exactly how
  it ends up pointed at DashScope endpoints later.
- Every `modelProviders` entry: `baseUrl` = your key's one valid endpoint,
  `envKey` = that env name, model `id`s taken from what the endpoint actually
  serves.
- `model.name` / `model.baseUrl`: your default model at the same endpoint.
- `security.auth.selectedType`: `"openai"` (the OpenAI-compatible API-key path).
- Reasoning-capable models take
  `"generationConfig": {"extra_body": {"enable_thinking": true}}`.

VSCode (user `settings.json`):

```json
"qwen-code.provider": "api-key"
```

> ⚠️ **Warning about the provider picker:** selecting "Coding Plan" in the
> extension's provider picker can *rewrite* `~/.qwen/settings.json` and re-point
> your key at coding-plan endpoints — if your key is a Token Plan key, that
> reintroduces the 401 you just fixed. With a hand-written config, prefer leaving
> the picker alone.

<a id="s5"></a>

## 5. ⚠️ Related gotchas collected along the way

- **The free-tier red herring.** Qwen's OAuth free tier was discontinued
  2026-04-15, producing a wave of identical 401 reports
  ([#3203](https://github.com/QwenLM/qwen-code/issues/3203),
  [#3335](https://github.com/QwenLM/qwen-code/issues/3335),
  [#3425](https://github.com/QwenLM/qwen-code/issues/3425)). If you were on the
  free OAuth tier, your fix is different: run `/auth` and switch to a paid plan
  or another provider. Don't let those threads convince you a *plan* key is
  dead — different disease, same symptom.
- **Token Plan output cap:** `max_tokens` tops out at 131,072 on the token-plan
  endpoint; if you configure thinking budgets, keep them well under that.
- **Console "valid" ≠ endpoint match.** The key-management page tells you the
  key exists and is active — it does not tell you which endpoint your tooling
  is sending it to.
- **Copying configs between machines copies the confusion too.** If machine A's
  config was fixed by switching endpoints (not by changing the key), copying
  just the key to machine B fixes nothing — copy the whole config.

<a id="s6"></a>

## 6. 🔍 Auditing and comparing machines

[`qwen-audit.sh`](qwen-audit.sh) emits a diffable report of the entire Qwen Code
surface — settings, auth type, providers, extension/CLI versions, and where key
material lives — **without ever printing a key** (length, 6-char prefix, and a
12-hex-char SHA-256 fingerprint only, which is enough to tell "same key" from
"different key" across machines).

```bash
./qwen-audit.sh > this-machine.txt          # config report
./qwen-audit.sh --live > this-machine.txt   # + real auth probe of 3 endpoints
diff other-machine.txt this-machine.txt
```

---

*Written by [Nathan Maine](https://github.com/NathanMaine) — from a real
debugging session across two machines. MIT licensed; if it saves you the
afternoon it cost me, pass it along.*
