# Termux Voice Coding Assistant

A simple voice-driven coding assistant for Termux that lets you speak coding requests and get responses from Claude Code via SSH.

## 🎯 What It Does

- **Press space** → Record your voice
- **Speech-to-text** → Transcribes your request
- **SSH to dev machine** → Sends request to Claude Code
- **Text-to-speech** → Speaks the response back
- **Display code** → Shows any code blocks on screen

## 🚀 Quick Start

### Prerequisites

1. **Development Machine**: Install Claude Code
   ```bash
   curl -sSL https://claude.ai/install.sh | bash
   ```

2. **Termux**: Install packages and setup
   ```bash
   wget https://raw.githubusercontent.com/pepijndevos/termux-voice-code/refs/heads/main/termux_voice_code.sh
   chmod +x termux_voice_code.sh
   ./termux_voice_code.sh install
   ./termux_voice_code.sh setup
   ```

3. **Termux:API App**: Install from F-Droid and grant microphone permissions

### Usage

```bash
./termux_voice_code.sh
```

**Controls:**
- `SPACE` - Record voice command
- `T` - Toggle TTS (local/API)
- `S` - Toggle STT (local/API)  
- `H` - Show conversation history
- `R` - Test audio functionality
- `Q` - Quit

## 🔧 Configuration

Edit settings:
```bash
./termux_voice_code.sh config
```

Key options:
- SSH connection details
- Local vs API audio processing
- OpenAI API key (for cloud audio)
- Whisper model size

## 🐛 Troubleshooting

**SSH Issues:**
- Check network connectivity
- Verify SSH key permissions: `chmod 600 ~/.ssh/termux_coding`

**Audio Issues:**
- Grant microphone permissions in Android settings
- Install Termux:API app from F-Droid
- Test with: `termux-tts-speak "test"`

**Claude Code Issues:**
- Verify installation on dev machine
- Check API key configuration
- Test with: `claude -p "hello" --output-format json`

## 📚 Commands

- `./termux_voice_code.sh` - Start the assistant (default)
- `./termux_voice_code.sh install` - Install required packages  
- `./termux_voice_code.sh setup` - Run setup wizard
- `./termux_voice_code.sh test` - Test functionality
- `./termux_voice_code.sh config` - Edit configuration
- `./termux_voice_code.sh help` - Show help

## 🎤 Audio Options

**Local Processing (Default):**
- Uses `termux-tts-speak` and `whisper.cpp`
- Offline, private, faster setup
- Lower quality transcription

**API Processing:**
- Uses OpenAI Whisper and TTS APIs
- Higher quality audio processing
- Requires internet and API key

Toggle between modes with `S` (STT) and `T` (TTS) keys in the interface.