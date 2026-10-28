# 🛡️ WHISPER SHIELD
### 🤫 When You Can't Scream, Just Whisper.

<p align="center">
  <img src="https://img.shields.io/badge/Built%20With-Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white" />
  <img src="https://img.shields.io/badge/AI%20Powered-On--Device%20ML-FF6F00?style=for-the-badge&logo=tensorflow&logoColor=white" />
  <img src="https://img.shields.io/badge/Privacy%20First-100%25%20On--Device-success?style=for-the-badge" />
  <img src="https://img.shields.io/badge/National%20Hackathon-Finalist-gold?style=for-the-badge" />
</p>

<p align="center">
  <a href="https://github.com/SHRI-26-arc/Whisper_Shield"><b>💻 GitHub</b></a> •
  <a href="#"><b>📱 APK Link</b></a> •
  <a href="#"><b>🎥 Demo Video</b></a>
</p>

---

### 📖 THE PROBLEM

In dangerous situations — in a cab, office, or at home — screaming for help can make things WORSE. Existing SOS apps need you to unlock your phone, open the app, and press a button. That's 10 seconds you don't have, and it's not discreet.

**We asked: What if help was just a whisper away?**

### 💡 OUR SOLUTION

**Whisper Shield** is an AI-powered safety co-pilot that detects ultra-low-volume distress whispers and triggers a **SILENT SOS** — without touching your phone.

No loud alarm. No bright screen. Just whisper and your trusted contacts get your live location.

### ✨ CORE FEATURES

- **🤫 Whisper Detection Engine:** Detects whispers as low as 15dB using on-device CNN model
- **🧠 Fear + Keyword AI:** Understands not just words like "help" / "bachao" but also trembling voice, crying, urgency
- **👻 Ghost Mode:** App disguises as Calculator / Notes. No one knows it's a safety app
- **🚨 Silent SOS Protocol:** Sends Live Location + 30-sec Stealth Audio + Battery % with zero sound/vibration
- **👨‍👩‍👧‍👦 Family Shield:** Family gets a live tracking link, like Uber, not just a text
- **📍 Offline First:** Works 100% offline. Audio never leaves your phone

### 🛠️ TECH STACK

**Frontend:** Flutter 3.22, Dart, Riverpod, Lottie
**AI Engine:** TensorFlow Lite, Vosk (On-Device STT), Custom CNN, NLP Keyword Spotting
**Backend:** Firebase Auth, Firestore Live Location, Node.js, Geolocator

### 🗄️ DATABASE

**Prototype (Current):** Hive Local DB + Local State. 100% Private. No server storage.
**Production (Future):** Firebase Firestore + MongoDB for anonymized safety patterns + 112 API Integration

### 🏗️ HOW IT WORKS

[ Mic Listening ] → [ Is it a Whisper? (<30dB) ]
      ↓ YES
[ On-Device AI: Keyword + Fear Score ]
      ↓ Score > 85%
[ SILENT SOS TRIGGERED → Family + Location Alert ]

### 👥 TEAM OF 4 - WORK DIVISION

**MEMBER 1 - Frontend: Stealth UI & Onboarding**
- Ghost UI (Calculator disguise), Onboarding, Triple-Shake Gesture
- Tech: Flutter, Sensors, Animations
- Deliverable: App that is safe to keep on phone

**MEMBER 2 - Frontend: SOS Dashboard & Family Shield**
- Live SOS Screen with Map, Audio Waveform, Family Live Tracking Link
- Tech: Flutter, Google Maps, Firebase Streams
- Deliverable: Makes emergency info clear in 2 seconds

**MEMBER 3 - AI Engine: Whisper Detection**
- Built Whisper CNN, Keyword spotting (Hinglish), Emotion detection
- Output: `{ is_whisper: true, fear_score: 92, keyword: "help" }`
- Tech: Python, TensorFlow, TFLite

**MEMBER 4 - Backend: SOS & Integration**
- SOS Relay API `POST /trigger-sos`, Background Location Service, Privacy Engine
- Tech: Node.js, Firebase, Background Services
- Deliverable: Full flow from Mic → AI → SOS

### 🚀 ROADMAP

**Phase 1 (Done):** Flutter App + Whisper AI + Silent SOS
**Phase 2 (Next):** 10 Indian Languages, Smartwatch Support, Auto-call 112 + Evidence PDF
**Phase 3 (Vision):** SMS SOS without Internet, Campus Safety Network, Police Heatmap Dashboard

### ▶️ HOW TO RUN

```bash
git clone https://github.com/SHRI-26-arc/Whisper_Shield.git
cd Whisper_Shield
flutter pub get
flutter run --release
### 🏆 OUR X-FACTOR

We are not building another SOS button. We are building the courage to whisper when you can't scream.
True Innovation is not adding features, it's removing the need to be loud to be safe.

<p align="center"><b>Made with ❤️ for a safer Bharat 🇮🇳</b></p>
