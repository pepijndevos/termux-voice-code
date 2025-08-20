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

**Single integrated script:**
- `termux_voice_code.sh` - Complete voice coding assistant with all functionality integrated
- `config.sh` - Optional configuration file (auto-created if needed)

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
./termux_voice_code.sh install

# OR install manually
pkg install openssh jq termux-api curl nano

# Install Termux:API app from F-Droid
# Grant microphone permissions

# Run complete setup wizard
./termux_voice_code.sh setup
```

**Usage:**
```bash
./termux_voice_code.sh
# Press space to record, interactive TUI with controls
```

## 🔧 How It Works

1. **Record**: `termux-microphone-record` captures audio to WAV file
2. **Transcribe**: Local whisper.cpp or OpenAI Whisper API converts speech to text  
3. **Query**: SSH to dev machine and run `claude -p "transcription" --output-format json`
4. **Speak**: Local `termux-tts-speak` or OpenAI TTS reads the response aloud
5. **Display**: Show responses and code blocks with basic formatting in a simple TUI

Features integrated in the single script:
- Interactive TUI with connection status and controls
- Local/API audio processing options (toggleable)
- Conversation history tracking
- Configuration management (auto-creates config.sh)
- Complete setup wizard with SSH key generation

## 🔧 Configuration Options

### Configuration Options
The script auto-creates `config.sh` with defaults, or you can edit it:
```bash
./termux_voice_code.sh config
```

Key settings:
- SSH connection details (host, user, key path)
- Claude Code installation path on dev machine
- Local vs API processing for STT/TTS
- Whisper model size (tiny, base, small, medium, large)
- OpenAI API key for cloud processing

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