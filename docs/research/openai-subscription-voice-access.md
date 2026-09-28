# OpenAI subscription access for realtime voice

## Answer

No. As of 2026-09-27, OpenAI offers no supported way for a third-party native macOS app to let a person sign in with a ChatGPT Plus, Pro, or Business plan and run OpenAI realtime speech-to-speech models on that plan. "Sign in with ChatGPT" for third parties is an identity-only sign-in that shares name, email, and profile picture, and explicitly does not share tokens or billing. The public Realtime and GPT-Live APIs accept only Platform API keys, workload-identity access tokens tied to an API service account, or ephemeral secrets minted from those, all billed to an API organization. Subscription-billed voice exists only inside OpenAI's own clients (ChatGPT apps and the Codex/ChatGPT desktop app). The open-source Codex harness contains that voice code path, but it is undocumented for third parties, gated by "client or rollout checks", and has no explicit terms permission. For ReadyPlayerTwo, ADR 0017 (person-supplied API key) stays correct, issue #29 stays open, and Set Up Voice should keep saying plainly that a ChatGPT subscription does not cover voice.

## Research date and method

- Date: 2026-09-27.
- Sources: OpenAI's help center, developer docs (`developers.openai.com`, which now redirects Codex docs to `learn.chatgpt.com`), policy pages on `openai.com/policies`, and the `openai/codex` source at commit `1cc7e23` (2026-09-28 UTC). Provider docs, model cards, license files, and repos for the alternatives.
- Some `openai.com` and `help.openai.com` pages block direct fetches, so they were read through a text-rendering proxy (`r.jina.ai`). The content is OpenAI's own page.
- Labels: **Verified** means read in a primary source. **Inferred** means reasoned from verified facts. **Unverified** means only a secondary source or untested.

## Findings per mechanism

### 1. "Sign in with ChatGPT" for third-party apps

**Verdict: identity only. It grants no model access and no plan billing. Verified.**

- OpenAI's help article (updated 2026-09-26) calls it "an identity-provider sign-in option that lets you use identity information from your ChatGPT account to create, link, or access an account with a supported external application." ([Help: Sign in with ChatGPT](https://help.openai.com/en/articles/20001410-sign-in-with-chatgpt))
- What the app receives: "only your name, email address, and profile picture". The feature "does not independently share ... Your files or tokens" or "Your billing information or other ChatGPT account data." (same source)
- Availability is limited to OpenAI Academy, ChatGPT Sites, and "select plugins and partner sites". Initial partners are Airtable, GitLab, HubSpot, Notion, Supabase, and Vercel. Any further access, such as ChatGPT Sites connected apps or ChatGPT Ads, needs a separate delegated authorization. None of the listed delegated scopes is model inference or voice. (same source)
- How to apply: the 2025 developer interest form at `openai.com/form/sign-in-with-chatgpt` returned a 404 on 2026-09-27. No public developer documentation or self-serve registration exists. **Verified (404 observed).** Partnership contact is the only route, and that is inferred.
- Realtime or voice coverage: none. Nothing in the article, the API reference, or the Realtime guides connects this sign-in to model usage.

### 2. Codex CLI and Codex app ChatGPT authentication

**Verdict: the token authorizes OpenAI's ChatGPT backend for Codex use only. It is not accepted by the public API. A subscription-billed voice path exists in Codex, but it is undocumented for third parties, gated, and not clearly permitted. Verified from source and docs, except where marked.**

- Two sign-in modes: "Sign in with ChatGPT for subscription access" and "Sign in with an API key for usage-based access". With an API key, "Codex uses standard API pricing instead of included ChatGPT plan credits." ([Codex authentication](https://learn.chatgpt.com/docs/auth); the old `developers.openai.com/codex/auth` URL 308-redirects here.)
- Tokens are cached in `~/.codex/auth.json` or the OS keyring, and OpenAI says: "treat `~/.codex/auth.json` like a password: it contains access tokens. Don't commit it, paste it into tickets, or share it in chat." (same source)
- Endpoints: under ChatGPT auth, Codex creates voice (WebRTC) calls at `https://chatgpt.com/backend-api/codex/realtime/calls`. Under API-key auth, it uses `https://api.openai.com/v1/realtime/calls`. See `codex-rs/codex-api/src/endpoint/realtime_call.rs` (test assertions) and `codex-rs/core/src/client.rs` (`create_realtime_call_with_headers`, which also attaches an `x-oai-attestation` header when the host supplies one). ([openai/codex](https://github.com/openai/codex))
- The WebSocket voice transport still requires an API key even for ChatGPT sessions. The source says "TODO(aibrahim): Remove this temporary fallback once realtime auth no longer requires API key auth for ChatGPT/SIWC sessions" and otherwise errors with "realtime conversation requires API key auth". (`codex-rs/core/src/realtime_conversation.rs`, `realtime_api_key`)
- Codex voice features: the CLI has an experimental `/voice` command. The ChatGPT desktop app has "ChatGPT Voice", powered by GPT-Live, for Plus, Pro, Business, Edu, and Enterprise. Voice in Desktop "uses your existing Codex usage budget at $0.05 per minute" and "isn't available via API key." ([ChatGPT Voice (desktop)](https://learn.chatgpt.com/docs/features/voice), [Pricing](https://learn.chatgpt.com/docs/pricing))
- Gating: the config reference says the `features.realtime_conversation` flag controls the "experimental `/voice` command in the Codex CLI" and that "Setting it to `true` does not bypass client or rollout checks." ([Configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference)) The source also distinguishes first-party originators (`is_first_party_originator`, `is_first_party_chat_originator` in `codex-rs/login/src/auth/default_client.rs`).
- Codex app-server: OpenAI documents it for "a deep integration inside your own product: authentication, conversation history, approvals, and streamed agent events." It supports `account/login/start` with `chatgpt`, and an experimental `chatgptAuthTokens` mode for "host apps that already own the user's ChatGPT auth lifecycle." ([Codex App Server](https://learn.chatgpt.com/docs/app-server)) The same page says the app-server "command and WebSocket transport are experimental and aren't supported for production workloads." Its method list does not document the `thread/realtime/*` methods. Those methods exist in source only, behind `experimentalApi` (`codex-rs/app-server-protocol/src/protocol/common.rs`).
- **Unverified and untested:** whether a non-first-party client that embeds app-server can start a subscription-billed voice call through `chatgpt.com/backend-api/codex/realtime/calls`. The attestation header and the documented "client or rollout checks" suggest it may be refused. Even if it worked, the session is a Codex agent thread (a coding and work harness), not a general companion voice session.
- Reuse in other apps: no OpenAI document grants permission. In [openai/codex discussion #8338](https://github.com/openai/codex/discussions/8338), an OpenAI maintainer (etraut-openai, 2026-02-09) wrote "I'm an engineer, not a lawyer" and said the terms and license "are quite permissive, and OSS projects like OpenCode are doing things similar". This is not a policy statement. Follow-up requests for an official answer (2026-05-05, 2026-07-20, 2026-08-27) are unanswered as of the research date.
- The feature request `openai/codex#10974`, cited in ReadyPlayerTwo issue #29, now returns 404 on GitHub.

### 3. Apps SDK and plugins, ChatGPT desktop voice, and "bring your own plan" programs

**Verdict: no program lets an external app consume a person's plan. Plugins run inside ChatGPT, not in your app. Verified.**

- Apps SDK is now documented as ChatGPT **plugins**: MCP servers plus optional UI that run in ChatGPT and Codex. The OAuth direction is reversed. ChatGPT or Codex is the OAuth client, "acting on behalf of the user" toward your server. ([Plugins authentication](https://developers.openai.com/plugins/build/auth))
- ChatGPT Voice "Live" (GPT-Live-1) "can also use the plugins and connected apps available to your account." ([Help: ChatGPT Voice](https://help.openai.com/articles/20001274)) A ReadyPlayerTwo plugin could therefore be called from ChatGPT's own voice UI under the person's plan. The voice, UI, and character would all be ChatGPT's, so this is not the desktop Companion. **Inferred.**
- ChatGPT plan voice allowances are consumer entitlements inside OpenAI clients: for example, Plus gets "3 hours with GPT-Live-1" per rolling 24 hours in Chat. (same source)
- Billing separation: "ChatGPT and the API platform have separate billing systems" and "API usage is billed separately from your ChatGPT subscription." ([Help: Managing billing](https://help.openai.com/en/articles/9039756-managing-billing-for-chatgpt-and-the-api-platform))
- No "bring your own plan" or OAuth model-access program appears in the OpenAI developer index ([developers.openai.com/llms.txt](https://developers.openai.com/llms.txt)) or the ChatGPT docs index ([learn.chatgpt.com/llms.txt](https://learn.chatgpt.com/llms.txt)). **Verified absence in the indexes.**

### 4. Credentials accepted by the Realtime API

**Verdict: API keys, workload-identity access tokens, or ephemeral client secrets minted from them. All are API-organization credentials. Verified.**

- "The OpenAI API accepts bearer credentials from API keys or from short-lived access tokens created with workload identity federation." ([API reference overview](https://developers.openai.com/api/reference/overview))
- Workload identity federation exchanges a workload's IdP token for "A service account in an API Platform project". It is for trusted workloads, not end-user ChatGPT accounts. Its Codex variant maps to managed ChatGPT workspace principals for Codex only. ([Workload identity federation](https://developers.openai.com/api/docs/guides/workload-identity-federation))
- Realtime WebRTC: the server uses "a standard API key" to call `/v1/realtime/calls`, or mints an ephemeral key via `/v1/realtime/client_secrets` with "a standard API key". ([Voice WebRTC guide](https://developers.openai.com/api/docs/guides/voice-webrtc))
- No ChatGPT session token is documented as valid on `api.openai.com`.

### 5. GPT-Live

**Verdict: exists. It is subscription-billed inside ChatGPT and API-billed ($0.05 per minute plus backend) for developers. There is no subscription path for third parties. Verified.**

- OpenAI introduced GPT-Live, a full-duplex voice model family (GPT-Live-1 and GPT-Live-1 mini), for ChatGPT Voice. ([Introducing GPT-Live](https://openai.com/index/introducing-gpt-live/))
- API: model `gpt-live-1` on a new endpoint `v1/live/sessions`. It is not available on `v1/realtime`. Pricing is "$0.05 per minute, billed per second. Backend model and tool usage is billed separately." The Free usage tier is unsupported. ([GPT-Live 1 model](https://developers.openai.com/api/docs/models/gpt-live-1), [GPT-Live 1 in the API](https://openai.com/index/introducing-gpt-live-1-in-the-api/))
- Auth: "a trusted server with an OpenAI project API key. Keep the key on the server." The WebRTC quickstart has the server exchange SDP via `POST /v1/live/sessions`. The GPT-Live guide does not document ephemeral client secrets. ([Getting started with GPT-Live](https://developers.openai.com/api/docs/guides/live), [Voice WebRTC guide](https://developers.openai.com/api/docs/guides/voice-webrtc?api=live))
- OpenAI reports GPT-Live-1 improves Full Duplex Bench by 30 points over GPT-Realtime-2.1. This is relevant if ReadyPlayerTwo later moves off `gpt-realtime-2.1`, but it does not change billing. GPT-Live's `v1/live/sessions` and delegation model would need a new Realtime Adapter.

### 6. Terms

See the next section. **Verdict: no clause authorizes third-party apps to use a person's ChatGPT subscription. Several clauses weigh against it. Verified quotes, inferred application.**

## Terms of use constraints

| Source | Excerpt | Relevance |
| --- | --- | --- |
| [Terms of Use](https://openai.com/policies/terms-of-use/) (effective 2026-01-01) | "You may not share your account credentials or make your account available to anyone else" | A third-party app holding ChatGPT tokens is at least arguably making the account available to other software. The account holder carries the risk. |
| Terms of Use | "Automatically or programmatically extract data or Output" (prohibited) | Programmatic use of a consumer ChatGPT session outside OpenAI clients is exposed to this clause. |
| Terms of Use | "circumvent any rate limits or restrictions or bypass any protective measures" (prohibited) | Faking a first-party originator or attestation to pass "client or rollout checks" would fall here. **Inferred.** |
| [Service Terms, s. 8](https://openai.com/policies/service-terms/) | "ChatGPT Voice Output is for non-commercial use only and may not be distributed or repackaged" | Consumer voice output carries a non-commercial limit that API output does not. |
| [Services Agreement](https://openai.com/policies/services-agreement/) (API, Business, Enterprise) | "Customer will not share Account access credentials or individual login credentials between multiple users." | Applies to Business workspaces too. |
| Services Agreement, s. 3.3(g) | "buy, sell, or transfer API keys from, to, or with a third party" (prohibited) | ReadyPlayerTwo must never supply or broker keys. The person-supplied key model in ADR 0017 is consistent with this. |
| Services Agreement, s. 2.2 | "the right to use OpenAI's API to integrate the Services into Customer Applications and to make Customer Applications available to End Users" | This is the sanctioned route for third-party apps, and it is API-billed. |
| [Codex auth docs](https://learn.chatgpt.com/docs/auth) | "treat `~/.codex/auth.json` like a password ... Don't ... share it" | Reading or reusing Codex tokens from ReadyPlayerTwo is out of bounds. |

## Alternatives for later

### Hosted providers

| Option | Auth / billing | Hardware | Latency | Quality notes | Integration notes | Sources |
| --- | --- | --- | --- | --- | --- | --- |
| Google Gemini Live API (`gemini-3.8-live`, stable) | Per-person Google AI Studio API key. The free tier is "Free of charge". Paid: audio in $0.005/min, audio out $0.018/min. On the free tier, content is used to improve products and humans may review it ("Do not submit sensitive, confidential, or personal information"). Only paid services may serve users in the EEA, Switzerland, or UK. Users must be 18+. API use is "for professional or business purposes, not for consumer use". Free-tier Live rate limits are shown only in AI Studio, not in the docs. | Cloud | Google describes it as "ultra-low latency audio-to-audio". No published ms figure. | Native audio, function calling, session management | WebSockets, client-to-server with ephemeral tokens recommended. The docs point to third-party integrations for WebRTC. A native Swift client over `URLSessionWebSocketTask` is feasible. **Inferred.** | [Pricing](https://ai.google.dev/gemini-api/docs/pricing), [Terms](https://ai.google.dev/gemini-api/terms), [Live API](https://ai.google.dev/gemini-api/docs/live), [Model](https://ai.google.dev/gemini-api/docs/models/gemini-3.8-live), [Rate limits](https://ai.google.dev/gemini-api/docs/rate-limits) |
| ElevenLabs Agents | Per-account API key. The Free plan includes 15 call minutes per month and 4 concurrent calls. Overage is $0.08/min, and LLM usage is billed separately. | Cloud | Not published on the pricing page | Cascaded agent platform with ElevenLabs voices | SDKs and WebRTC/WebSocket (not checked in depth) | [Agents pricing](https://elevenlabs.io/pricing/agents) |
| Hume EVI (EVI 3 / EVI 4 mini) | Per-account API key. The Free plan includes 5 EVI minutes per month. Paid plans start at $3/month with 40 minutes. | Cloud | Not published on the pricing page | Emotion-aware speech-to-speech | WebSocket API (not checked in depth) | [Hume pricing](https://www.hume.ai/pricing) |

None of these offers a consumer-subscription sign-in. Gemini's free tier is the only one large enough for daily Companion use, and its data-use and EEA/UK/CH terms conflict with ReadyPlayerTwo's privacy posture.

### Local and open-source (Apple Silicon)

| Option | License | Hardware / download | Latency | Quality notes | Integration notes | Sources |
| --- | --- | --- | --- | --- | --- | --- |
| Kyutai Moshi (end-to-end, full duplex) | Code MIT (Python) and Apache (Rust). Weights CC-BY 4.0, which allows commercial use with attribution. | 7B. MLX q4 repo about 5.2 GB, q8 about 8.6 GB. Tested by Kyutai on a MacBook Pro M3. | Theoretical 160 ms. About 200 ms measured on an L4 GPU. No published Mac figure. | Natural turn-taking. Knowledge and reasoning are limited (7B, 2024 model). | `moshi_mlx` (Python). `kyutai-labs/moshi-swift` (MIT, MLX Swift) is "experimental" and "a proof of concept", last pushed 2025-06. | [moshi README](https://github.com/kyutai-labs/moshi), [moshi-swift](https://github.com/kyutai-labs/moshi-swift), [moshiko-mlx-q4](https://huggingface.co/kyutai/moshiko-mlx-q4) |
| NVIDIA NemotronLabs VoiceChat 11B (end-to-end, full duplex, tool calling) | OpenMDW 1.1 (permissive) | 11B. The MLX 4-bit community port is about 9.2 GB. | About 450 ms turn-taking, 480 ms interruption, measured on NVIDIA GPUs. Mac latency unverified. | Newer than Moshi, English only, #2 open model on VoiceBench | `mlx-audio` STS (Python). No Swift port found. | [Model card](https://huggingface.co/nvidia/NVIDIA-NemotronLabs-VoiceChat-11B), [mlx-audio](https://github.com/Blaizzy/mlx-audio) |
| Liquid LFM2.5-Audio 1.5B (end-to-end, interleaved) | LFM Open License v1.0. Commercial use is restricted at or above $10M annual revenue. | 1.5B, about 3.7 GB repo. llama.cpp GGUFs available. | Designed "with low latency and real time conversation in mind". No figure. | Small model, so expect limited depth | `mlx-audio` (8-bit), llama.cpp | [Model card](https://huggingface.co/LiquidAI/LFM2.5-Audio-1.5B) |
| NVIDIA PersonaPlex 7B (Moshi-based, full duplex) | Code MIT. Weights under the NVIDIA Open Model License, and the model is gated. | About 17 GB repo. Targets NVIDIA GPUs. | Not published for Mac | Persona and voice conditioning | No MLX or Swift path found | [personaplex](https://github.com/NVIDIA/personaplex), [Model](https://huggingface.co/nvidia/personaplex-7b-v1) |
| Cascade: FluidAudio (Parakeet ASR + EOU, Kokoro or PocketTTS, Silero VAD, echo cancellation) + local LLM | FluidAudio Apache-2.0. Parakeet TDT v3 CC-BY 4.0. Kokoro-82M Apache-2.0. PocketTTS weights CC-BY 4.0. | Core ML on the Neural Engine. Parakeet v3 Core ML about 3.6 GB repo (all variants). Kokoro about 0.36 GB. | Parakeet EOU streaming at 320 ms chunks, 4.88% WER on LibriSpeech (M2). Kokoro Core ML synthesized 42 characters in 0.44 s on an M4 Pro. PocketTTS gives about 200 ms to first audio on CPU. LLM latency depends on the model. | Best native-Swift fit. Quality is capped by the local LLM. | Swift Package with a native API, already used by many macOS menu-bar apps. Pair with `mlx-swift-lm` (MIT) or llama.cpp (MIT) for the LLM. | [FluidAudio](https://github.com/FluidInference/FluidAudio), [Benchmarks](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md), [Parakeet v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3), [Kokoro](https://huggingface.co/hexgrad/Kokoro-82M), [pocket-tts](https://github.com/kyutai-labs/pocket-tts), [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) |
| Cascade: Apple SpeechAnalyzer + Foundation Models + system TTS | Apple SDK. No model cost. | macOS 26+ for SpeechAnalyzer and Foundation Models, on devices that support Apple Intelligence. There is no bundled download because the models ship with the OS. | Not published | The on-device LLM is small. The Private Cloud Compute (PCC) model (macOS 27+) adds 32K context and stronger reasoning, with a per-person daily quota that iCloud+ can raise. | Pure Swift. However, PCC production use requires App Store distribution, the Small Business Program, and a managed entitlement. It is available only for testing via TestFlight or ad hoc builds, so it does not fit a Homebrew-tap release. ReadyPlayerTwo's macOS 15 floor would also need raising. | [Foundation Models](https://developer.apple.com/documentation/foundationmodels), [PCC guide](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute), [PCC eligibility](https://developer.apple.com/private-cloud-compute/), [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer) |
| WhisperKit (STT alternative) | MIT | Core ML, many model sizes | Not measured here | Mature Whisper runtime | Swift Package | [WhisperKit](https://github.com/argmaxinc/WhisperKit) |

Download sizes are the whole Hugging Face repo, as reported by the Hub API, and usually include several variants. A single variant is smaller.

## Open questions

1. Should the owner contact OpenAI partnerships to ask about Sign in with ChatGPT model-access or voice scopes for a Homebrew-distributed Mac app? The public form is gone, so a direct contact is the only route.
2. Would OpenAI give a written answer on embedding Codex app-server with ChatGPT sign-in (the unanswered discussion #8338 asks)? A yes would still leave the voice path experimental and Codex-thread-bound.
3. Is a free-tier Gemini Live option acceptable, given its training and human-review data use and its exclusion of EEA, UK, and CH users? If not, Gemini is a paid-key option comparable to OpenAI.
4. Is a local voice mode acceptable at lower conversational quality, with a multi-GB model download, as an offline or no-key option behind the same Voice Session seam?
5. Would moving to GPT-Live-1 (`v1/live/sessions`, server-side API key, no documented ephemeral secret) change the credential-broker design in ADR 0015 and ADR 0017? This needs a separate spike.
6. Recheck quarterly (per issue #29): the Sign in with ChatGPT help article, the Codex auth and app-server docs, and the `realtime_api_key` TODO in `openai/codex`.

## Sources

- OpenAI Help: [Sign in with ChatGPT](https://help.openai.com/en/articles/20001410-sign-in-with-chatgpt), [ChatGPT Voice](https://help.openai.com/articles/20001274), [Managing billing for ChatGPT and the API platform](https://help.openai.com/en/articles/9039756-managing-billing-for-chatgpt-and-the-api-platform)
- OpenAI ChatGPT and Codex docs: [Authentication](https://learn.chatgpt.com/docs/auth), [Codex App Server](https://learn.chatgpt.com/docs/app-server), [ChatGPT Voice (desktop)](https://learn.chatgpt.com/docs/features/voice), [Pricing](https://learn.chatgpt.com/docs/pricing), [Configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference), [Docs index](https://learn.chatgpt.com/llms.txt)
- OpenAI API docs: [API reference overview](https://developers.openai.com/api/reference/overview), [Workload identity federation](https://developers.openai.com/api/docs/guides/workload-identity-federation), [Voice WebRTC guide](https://developers.openai.com/api/docs/guides/voice-webrtc), [Getting started with GPT-Live](https://developers.openai.com/api/docs/guides/live), [GPT-Live 1 model](https://developers.openai.com/api/docs/models/gpt-live-1), [Plugins authentication](https://developers.openai.com/plugins/build/auth), [Developer index](https://developers.openai.com/llms.txt), [Codex as a platform](https://developers.openai.com/blog/codex-as-a-platform)
- OpenAI announcements: [Introducing GPT-Live](https://openai.com/index/introducing-gpt-live/), [GPT-Live-1 in the API](https://openai.com/index/introducing-gpt-live-1-in-the-api/)
- OpenAI policies: [Terms of Use](https://openai.com/policies/terms-of-use/), [Service Terms](https://openai.com/policies/service-terms/), [Services Agreement](https://openai.com/policies/services-agreement/)
- OpenAI source: [openai/codex](https://github.com/openai/codex) at `1cc7e23` (`codex-rs/core/src/realtime_conversation.rs`, `codex-rs/core/src/client.rs`, `codex-rs/codex-api/src/endpoint/realtime_call.rs`, `codex-rs/app-server-protocol/src/protocol/common.rs`, `codex-rs/login/src/auth/default_client.rs`), [Discussion #8338](https://github.com/openai/codex/discussions/8338)
- Google: [Gemini API pricing](https://ai.google.dev/gemini-api/docs/pricing), [Gemini API terms](https://ai.google.dev/gemini-api/terms), [Live API](https://ai.google.dev/gemini-api/docs/live), [Gemini 3.8 Live](https://ai.google.dev/gemini-api/docs/models/gemini-3.8-live), [Rate limits](https://ai.google.dev/gemini-api/docs/rate-limits)
- Other hosted: [ElevenLabs Agents pricing](https://elevenlabs.io/pricing/agents), [Hume pricing](https://www.hume.ai/pricing)
- Local: [kyutai-labs/moshi](https://github.com/kyutai-labs/moshi), [kyutai-labs/moshi-swift](https://github.com/kyutai-labs/moshi-swift), [kyutai-labs/pocket-tts](https://github.com/kyutai-labs/pocket-tts), [kyutai-labs/unmute](https://github.com/kyutai-labs/unmute) (Linux and CUDA only, not Mac), [NVIDIA NemotronLabs VoiceChat 11B](https://huggingface.co/nvidia/NVIDIA-NemotronLabs-VoiceChat-11B), [NVIDIA PersonaPlex](https://github.com/NVIDIA/personaplex), [LiquidAI LFM2.5-Audio](https://huggingface.co/LiquidAI/LFM2.5-Audio-1.5B), [FluidAudio](https://github.com/FluidInference/FluidAudio), [Parakeet TDT v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3), [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M), [mlx-audio](https://github.com/Blaizzy/mlx-audio), [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm), [WhisperKit](https://github.com/argmaxinc/WhisperKit)
- Apple: [Foundation Models](https://developer.apple.com/documentation/foundationmodels), [Private Cloud Compute guide](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute), [Accessing Private Cloud Compute](https://developer.apple.com/private-cloud-compute/), [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer)
