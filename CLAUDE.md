# CLAUDE.md - Termux Voice Coding Assistant

## 🎯 Project Goal

Build a simple voice-driven coding assistant for Termux:
- Press space to record voice
- Transcribe speech to text  
- Send to Claude Code via SSH
- Speak the response back
- Display any code blocks

No fancy features - just the basics working.

## 🏗️ Simple Flow

```
[Record Audio] → [Speech-to-Text] → [SSH to Dev Machine] → [Claude Code] → [Text-to-Speech + Display]
```

## 📁 Files

- `config.sh` - Basic SSH and file path settings
- `audio.sh` - Record audio, speech recognition, text-to-speech
- `claude.sh` - SSH to dev machine and run Claude Code
- `voice_assistant.sh` - Main script that ties it all together

## 🚀 Setup

**On your development machine:**
```bash
# Install Claude Code
curl -sSL https://claude.ai/install.sh | bash

# Test it works
claude -p "hello world" --output-format json
```

**In Termux:**
```bash
# Install packages automatically
./voice_coding_assistant.sh install

# OR install manually
pkg install openssh jq termux-api curl nano

# Install Termux:API app from F-Droid
# Grant microphone permissions

# Run complete setup wizard
./voice_coding_assistant.sh setup
```

**Usage:**
```bash
./voice_coding_assistant.sh
# Press space to record, it handles the rest
```

## 🔧 How It Works

1. **Record**: `termux-microphone-record` captures audio to WAV file
2. **Transcribe**: OpenAI Whisper API converts speech to text  
3. **Query**: SSH to dev machine and run `claude -p "transcription" --output-format json`
4. **Speak**: `termux-tts-speak` reads the response aloud
5. **Display**: Show any code blocks with basic formatting

That's it. No connection pools, no fancy TUI, no multi-user anything. Just a working voice coding assistant.

## 🔧 Configuration Options

### Advanced Audio Settings
Edit `config.sh` to customize:
- Recording timeout duration
- TTS voice parameters (rate, pitch)
- Whisper model size (tiny, base, small, medium, large)
- Audio file formats and quality

### SSH Optimization
For faster connections, add to `~/.ssh/config`:
```bash
Host dev-machine
    HostName your-dev-machine.local
    User your-username
    IdentityFile ~/.ssh/termux_coding
    ControlMaster auto
    ControlPath ~/.ssh/control:%h:%p:%r
    ControlPersist 10m
```

### Performance Tuning
- Use `whisper-tiny` model for faster local processing
- Implement conversation history limits to reduce memory usage
- Add caching for repeated commands

## 🐛 Troubleshooting

### Common Issues

1. **SSH Connection Fails**
   - Check network connectivity
   - Verify SSH key permissions: `chmod 600 ~/.ssh/termux_coding`
   - Test manual SSH: `ssh -i ~/.ssh/termux_coding user@host`

2. **Audio Recording Fails**
   - Grant microphone permissions in Android settings
   - Install Termux:API app from F-Droid
   - Test: `termux-microphone-record -f test.wav -l 1`

3. **TTS Not Working**
   - Check available engines: `termux-tts-engines`
   - Install Google TTS from Play Store
   - Test: `termux-tts-speak "test"`

4. **Claude Code Errors**
   - Verify Claude Code installation on dev machine
   - Check API key configuration
   - Test: `claude -p "hello" --output-format json`

### Debug Mode
Enable verbose logging by adding to `config.sh`:
```bash
DEBUG=true
set -x  # Enable bash debugging
```

## 🎯 Future Enhancements

### Phase 2 Features
- Conversation context preservation
- Code diff visualization
- File operation commands ("open file X", "save to Y")
- Voice-driven git operations
- Integration with popular IDEs

### Mobile Optimizations
- Battery usage optimization
- Background processing
- Notification integration
- Widget support for quick access

### Advanced Features
- Multi-language support
- Custom voice commands/shortcuts
- Integration with project management tools
- Voice-driven documentation generation

## 📚 Resources

- [Claude Code SDK Documentation](https://docs.anthropic.com/en/docs/claude-code/setup)
- [Termux Wiki](https://wiki.termux.com/)
- [whisper.cpp Repository](https://github.com/ggml-org/whisper.cpp)
- [Bash TUI Programming Guide](https://github.com/dylanaraps/writing-a-tui-in-bash)