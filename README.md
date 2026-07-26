# Gemma Edu — Human-Guided Adaptive Learning, Online and Offline

**Subtitle:** A multilingual educational companion powered by Gemma 4 that guides learners step by step, generates interactive activities, and updates their progression in real time.

**Track:** Education & Cultural Localization

---

## 💡 Inspiration

*What local problem are you solving today?*

In many African learning environments, students do not only need access to information. They need someone — or something — that can accompany them patiently, explain a concept in several ways, ask the right question, and adapt when they make a mistake.

This challenge is particularly important in Madagascar, where learners may study in French while thinking and communicating more naturally in Malagasy. Many educational tools are not localized enough, and most AI applications still depend heavily on a permanent internet connection.

**The numbers behind the problem:**

- School completion drops sharply as students advance through the system: in 2022, only **62% of girls and 57% of boys** completed primary school, falling to just **34.6% of girls and 30.9% of boys** completing secondary school, with a gross enrollment rate of only **6%** in higher education. *(UNESCO Institute for Statistics, cited by AllAfrica, 2026 — [source](https://fr.allafrica.com/stories/202606150630.html))*
- At the national **Baccalauréat** exam, the 2024 pass rate for the Antananarivo province was **56.31%** (down from 57.31% in 2023), with the general track at only **54.88%**, and the weakest series (A1) passing at under **46%**. *(AllAfrica, "Baccalauréat 2024," August 2024 — [source](https://fr.allafrica.com/stories/202408240104.html))*
- Only about **20% of Madagascar's population** was online as of late 2025 (~6.7 million users out of ~32.9 million people), leaving roughly **80% offline** — ranking the country among the 10 lowest in the world for internet adoption. *(Kepios "Digital Report," 2025–2026, via 2424.mg / Newsmada — [source](https://2424.mg/digital-report-2025-madagascar-classe-10eme-pays-avec-le-plus-faible-niveau-dadoption-de-linternet-au-monde/))*

These figures frame the two problems Gemma Edu directly targets: a steep, well-documented drop-off in learning outcomes as students progress through the system, and a connectivity gap that makes "online-only" AI tutoring unusable for most of the population.

A conventional chatbot usually follows this pattern:

> *Question → Direct answer*

However, receiving the answer is not the same as understanding the lesson.

Gemma Edu was designed around a different approach:

> *Question → Diagnostic → Guided reasoning → Explanation → Practice → Evaluation → Progress update*

Its main purpose is not to complete schoolwork for the learner. It accompanies the learner step by step, keeping the learner active in the reasoning process and the teacher responsible for educational decisions — Gemma assists both by generating, evaluating, adapting, and organizing educational content.

---

## 🛠️ How we built it

*Which Gemma model did you use? Did you use RAG, prompt engineering, or fine-tuning? What frameworks did you use?*

Gemma Edu is a hybrid, human-and-AI educational system combining several complementary AI strategies on top of **Gemma 4**, rather than relying on a single technique.

### Two Gemma 4 configurations, two contexts

- **`gemma-4-31b-it` (online, hosted)** — accessed through an OpenAI-compatible client pointed at the Gemini API, used for richer generation tasks such as building the structured tutorial plan (script + slide breakdown) and deciding whether a new video request should reuse an existing tutorial or trigger a new generation. Gemma sits at the very core of the video creation pipeline: it doesn't just write the script, it also plans which image slides to use and how long each should last, and — through the reuse-decision logic — whether a new video even needs to be generated at all. Every meaningful decision in the pipeline routes back through Gemma.
- **`unsloth/gemma-4-E2B-it` (offline, fine-tuned, 4-bit)** — fine-tuned locally with **Unsloth**, **TRL (`SFTTrainer` / `SFTConfig`)**, and **Hugging Face Datasets**, using **LoRA** adapters (`q_proj, k_proj, v_proj, o_proj, gate_proj, up_proj, down_proj`, r=16) on a custom Malagasy conversational and educational dataset (train/validation/test JSONL, chat-template formatted). The resulting adapters are saved locally and the final fine-tuned version is pushed to the Hugging Face Hub for reuse and offline inference:

  ```python
  HF_REPO = "Nandrasana2611/mpanabe-gemma2b-lora"
  ```

### Prompt engineering & structured output

Rather than free-form text, Gemma is prompted to return **structured JSON** (`reponse`, `action`, `choix`), which the application parses and validates before executing the requested function — this is what powers real-time progression tracking (see below) and reliable activity generation (quiz, true/false, memory game).

### RAG (online) + fine-tuning (offline) for Malagasy localization

- **Online mode:** retrieval-augmented generation using a Malagasy dictionary (*rakibolana*) attached as a source document to the chat request through a `with_rag` flag, giving Gemma relevant definitions, translations, and culturally appropriate vocabulary before it answers.
- **Offline mode:** the fine-tuned Gemma model above lets the device respond in Malagasy without depending on a live retrieval service, preserving essential localized educational support where connectivity is limited.

### Frameworks & tools

- **Transformers ecosystem:** Unsloth, TRL, Hugging Face Datasets & Hub
- **Backend:** FastAPI (chat endpoint, video-tutorial endpoint, static media serving)
- **Storage:** SQLite (local learner profile, conversations, competencies, scores, progression, and — server-side — generated tutorial metadata to avoid regenerating near-duplicate videos)
- **Media pipeline:** MoviePy, OpenCV (slide composition & subtitle rendering), a custom Malagasy TTS module, and Whisper (`mg` language) for timestamped transcription/subtitles
- **Mobile app:** Flutter / Dart
- **Landing page:** React + pure CSS

---

## 🚀 The Prototype

[Insert Link to your 2-minute Demo Video here]

[Insert Link to your Kaggle Notebook / GitHub Repo here]

---

## 🧗 Challenges we ran into

*What was the hardest part of building this in one day?*

- **Making a full pedagogical loop reliable, not just a chatbot.** Getting Gemma to consistently return valid structured JSON (`reponse` / `action` / `choix`) — instead of free text — so the app could safely trigger functions like `add_user_progression` or `generate_quiz` took careful prompt engineering and validation, especially under time pressure.
- **Malagasy support with almost no existing tooling.** There is very little off-the-shelf support for Malagasy (TTS, ASR, dictionaries), so we had to combine a custom TTS pipeline, Whisper with the `mg` language setting, and our own fine-tuning dataset just to get a usable offline conversational experience.
- **Fitting fine-tuning into a one-day timeline.** Preparing a Malagasy instruction dataset, fine-tuning `gemma-4-E2B-it` with Unsloth/LoRA on Colab, validating the reloaded model, and pushing it to the Hub all had to happen alongside building the rest of the product.
- **Assembling a full video-generation pipeline from scratch.** Turning a text sujet into a plan (script + slides), synthesizing Malagasy audio, generating timestamped subtitles, composing image slides, and merging everything into a final video required orchestrating several independent tools (LLM planning, TTS, Whisper, OpenCV, MoviePy) into one coherent, resilient flow.
- **Avoiding redundant work without losing flexibility.** Once video generation worked, we still had to decide *when* an existing tutorial should be reused versus regenerated — we didn't want a rigid exact-match rule, so we delegated that judgment to Gemma itself, comparing the new request against existing tutorials for the same context.
- **Balancing "online-enriched" vs "fully offline" behavior.** Deciding which features could gracefully degrade offline (core tutoring, quizzes, progression) versus which genuinely needed connectivity (RAG dictionary lookup, video tutorial generation, sync) shaped a lot of the architecture decisions made in a single day.

---

## 🌱 Beyond the Core Loop

*(Additional context we wanted to preserve alongside the required sections above.)*

### Interactive activities and educational games

Gemma Edu can transform a lesson or learning difficulty into interactive activities, generated according to the ongoing conversation and the learner's progression:

- **Quiz** — multiple-choice questions adapted to the learner's level and recent mistakes
- **True or false** — short statements the learner evaluates to quickly verify understanding
- **Memory game** — concepts, terms, definitions, images, or answers turned into matching pairs
- **Timed challenge** — questions answered within a limited duration to reinforce fluency and motivation

### Real-time progression through function calling

After an exercise, Gemma evaluates the response and can request an application function (`update_skill_status`, `save_learning_difficulty`, `generate_user_cursus`, `give_last_user_info`, etc.) to update the relevant competency in real time — *Mastered*, *In progress*, *To reinforce*, or *Not yet evaluated* — making progression part of the tutoring process rather than a separate static dashboard.

### Teacher experience

Gemma Edu includes a focused teacher page rather than a complex school-management platform: creating a lesson, preparing an exercise, generating a quiz, reviewing class progression, identifying concepts that need reinforcement, generating a targeted activity, and viewing learner progress. The teacher remains in control — Gemma can suggest an activity or identify a common difficulty, but the teacher decides whether the content is used, modified, or rejected.

### File and exercise analysis

The application supports attaching files, images, and educational documents for selected online processing services. This is not the main focus of the current prototype — advanced handwritten-copy analysis remains an area for further development.

### Demonstration scenario

1. A learner asks for help with fractions.
2. Gemma asks a diagnostic question.
3. The learner selects an incorrect answer.
4. Gemma identifies the misunderstanding.
5. The learner receives a step-by-step explanation.
6. Gemma generates a short quiz.
7. The learner completes the activity.
8. The model evaluates the answers.
9. A function updates the relevant competency in SQLite.
10. The progression interface displays the new status.
11. The learner can continue with a memory game or true-or-false activity.
12. The teacher page can show the concept that needs reinforcement.

The same core flow works in Malagasy using the offline fine-tuned model, while online mode can enrich the response through dictionary-based RAG.

### Impact

Gemma Edu aims to make personalized educational support more accessible in contexts where students receive limited individual attention, educational resources are not localized, internet access is unstable, teachers need assistance creating activities, and learners require explanations in Malagasy or bilingual form.

> *Gemma Edu does not simply answer the learner. It guides, evaluates, adapts, and grows with them.*
