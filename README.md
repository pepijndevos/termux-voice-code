# Termux Voice Coding Assistant

A voice-enabled Claude Code TUI for Termux that lets you speak coding requests via SSH to your development machine.

## 🎯 What It Does

- **Ctrl+Space** → Record your voice command
- **Enter** → Stop recording and review transcription
- **Enter again** → Send to Claude Code on dev machine
- **Text-to-speech** → Claude speaks responses back via MCP
- **Display code** → Shows code blocks visually

## 🏗️ Architecture

```
[Termux Phone] --SSH--> [Dev Machine Claude Code] --SSH--> [Termux TTS MCP Server]
      |                           |
   Voice Input              Voice Output
```

- **claude_voice.py**: Main TUI that SSHs to Claude with voice input via Ctrl+Space
- **tts_mcp_server.py**: MCP server providing text-to-speech tool to Claude
- **voice_config.ini**: Configuration for SSH, OpenAI Whisper, and TTS settings

## 🚀 Quick Start

### Prerequisites

**On Development Machine:**
```bash
# Install Claude Code
curl -sSL https://claude.ai/install.sh | bash

# Verify installation
claude --version
```

**In Termux:**
```bash
# Install required packages
pkg install python openssh termux-api rust

# Install Termux:API app from F-Droid
# Grant microphone and TTS permissions in Android settings

# Install Python dependencies
pip install openai mcp

# Setup SSH key for dev machine access
ssh-keygen -t ed25519 -f ~/.ssh/termux_coding
ssh-copy-id -i ~/.ssh/termux_coding user@your-dev-machine

# Setup SSH server on Termux (for MCP reverse connection)
pkg install openssh
passwd  # Set password for SSH
sshd    # Start SSH server (runs on port 8022)

# Copy your dev machine's SSH public key to Termux
# This allows dev machine to SSH back to Termux for TTS
cat ~/.ssh/id_ed25519.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

### Configuration

```bash
# Copy example config
cp voice_config.ini.example voice_config.ini

# Edit with your settings
nano voice_config.ini
```

Required settings:
- **[ssh]**: Your dev machine hostname, username, SSH key path
- **[claude]**: Path to claude binary on dev machine
- **[openai]**: API key from https://platform.openai.com/api-keys
- **[tts]**: pitch and rate for termux-tts-speak (1.0 = normal)

### Usage

```bash
# Start in project directory specified in config
python claude_voice.py

# Or override working directory via CLI
python claude_voice.py ~/code/my-project

# With custom config file
python claude_voice.py --config my-config.ini ~/code/my-project
```

**Controls:**
- **Ctrl+Space** - Start recording voice command
- **Enter** - Stop recording (then review transcription)
- **Enter again** - Send transcription to Claude
- **Ctrl+C** - Exit

## 🔧 How It Works

### Voice Input Flow
1. Press Ctrl+Space → starts audio recording
2. Speak your request (e.g., "add error handling to the login function")
3. Press Enter → stops recording
4. Whisper API transcribes audio → text appears in input field
5. Review transcription, press Enter to send to Claude

### Claude Response with TTS
1. Claude processes your request via SSH on dev machine
2. Claude writes/edits code using normal tools
3. Claude uses `mcp__termux-tts__speak` tool to speak a summary
4. TTS MCP server on Termux receives text and speaks it aloud
5. You hear the response and see code blocks on screen

### MCP Server Connection
- Your dev machine SSHs back to Termux (port 8022) to run tts_mcp_server.py
- Uses stdio transport (not TCP)
- Auto-detects Termux IP from SSH connection
- FastMCP framework handles protocol details

## 🎤 Configuration Options

### SSH Optimization
Add to `~/.ssh/config` on Termux for faster connections:
```
Host dev-machine
    HostName your-dev-machine.local
    User your-username
    IdentityFile ~/.ssh/termux_coding
    ControlMaster auto
    ControlPath ~/.ssh/control:%h:%p:%r
    ControlPersist 10m
```

### TTS Settings
In `voice_config.ini`:
```ini
[tts]
pitch = 1.0  # 0.5 to 2.0
rate = 2.0   # 0.5 to 2.0 (2.0 = 2x speed)
```

### Working Directory
```bash
# Use config default
python claude_voice.py

# Override for specific project
python claude_voice.py ~/code/different-project
```

## 🐛 Troubleshooting

### SSH Connection Issues
- Verify network connectivity: `ping your-dev-machine`
- Check SSH key permissions: `chmod 600 ~/.ssh/termux_coding`
- Test manual connection: `ssh -i ~/.ssh/termux_coding user@host`

### Audio Recording Fails
- Install Termux:API app from F-Droid (not Play Store)
- Grant microphone permissions in Android settings
- Test: `termux-microphone-record -f test.m4a -l 5`

### TTS Not Working
- Check TTS engines: `termux-tts-engines`
- Install Google TTS from Play Store if needed
- Test: `termux-tts-speak -r 2.0 "testing"`

### MCP Connection Failed
- Ensure sshd is running on Termux: `sshd`
- Check Termux's SSH port (8022): `logcat -s 'sshd:*'`
- Verify dev machine can SSH to Termux: `ssh -p 8022 termux@phone-ip whoami`

### Whisper API Errors
- Verify OpenAI API key is valid
- Check internet connectivity
- Ensure audio file is not too short (speak for at least 1-2 seconds)

## 📁 Files

- **claude_voice.py**: Main application with voice TUI
- **tts_mcp_server.py**: MCP server for text-to-speech
- **voice_config.ini**: Your configuration (not in git)
- **voice_config.ini.example**: Template configuration
- **CLAUDE.md**: Project instructions for Claude Code

## 📚 Resources

- [Claude Code Documentation](https://docs.anthropic.com/en/docs/claude-code/setup)
- [MCP Specification](https://modelcontextprotocol.io/)
- [Termux Wiki](https://wiki.termux.com/)
- [OpenAI Whisper API](https://platform.openai.com/docs/guides/speech-to-text)

## 🔐 Security Notes

- Never commit `voice_config.ini` (contains API keys)
- Use SSH keys, not passwords
- Restrict SSH access on both Termux and dev machine
- OpenAI Whisper API processes your audio on their servers
