# Voyage Voice and Sound Review

## Product decision

Voyage should be recognizable with its voice muted. The core sound language is:

- a quiet cabin bed for presence, controlled independently;
- brief semantic cues for events such as takeoff power, gear, cruise, touchdown, and passport stamping;
- haptics paired with direct manipulation and major physical events;
- spoken check-ins as an explicit opt-in, never restored by a general speaker button.

This keeps the focus session calm, makes sound useful rather than decorative, and avoids surprising users with a system voice they did not choose.

## Voice-provider evaluation

| Option | Strengths | Costs and risks | Voyage fit |
| --- | --- | --- | --- |
| Apple `AVSpeechSynthesizer` | Free, offline, private, already integrated | Compact voices can sound synthetic; enhanced voices must be installed by the user | Keep as the optional offline fallback with preview |
| OpenAI `gpt-4o-mini-tts` | Natural speech, controllable delivery, official speech endpoint | Network latency, usage cost, disclosure requirement, API key cannot ship safely in an iOS binary | Good build-time generator for bundled fixed scripts |
| ElevenLabs Flash / Multilingual | Natural delivery and low-latency options | Runtime key must live behind a server; free output is noncommercial with attribution and the free API has voice-library limits | Good build-time generator after commercial rights and voice are chosen |
| Kokoro on iOS | Open-source/on-device and private | Current Swift ports require iOS 18, add dependencies and large model assets, conflicting with Voyage's iOS 17/no-dependency baseline | Revisit only if the deployment target changes |

## Recommended production path

1. Ship nonverbal sound cues plus opt-in Apple speech now.
2. Run a small listening test using the actual short Voyage scripts, not generic voice demos.
3. Generate the chosen phrases during development using OpenAI or ElevenLabs and bundle compressed audio. Do not call a cloud TTS provider during a focus flight.
4. Keep dynamic details visible on screen; spoken audio should remain short and need not narrate every variable.
5. Store provider credentials only in a local build environment or server secret store. Never put them in the app bundle, source, `Info.plist`, or a committed configuration file.

## Sources

- OpenAI GPT-4o mini TTS: https://developers.openai.com/api/docs/models/gpt-4o-mini-tts
- ElevenLabs text to speech: https://elevenlabs.io/docs/overview/capabilities/text-to-speech
- ElevenLabs billing and commercial-use notes: https://elevenlabs.io/docs/overview/administration/billing
- Kokoro iOS Swift port: https://github.com/mlalma/kokoro-ios
