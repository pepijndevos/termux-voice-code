#!/data/data/com.termux/files/usr/bin/bash
# termux_voice_code.sh - Consolidated voice coding assistant for Termux
# Single file version with all functionality included

set -euo pipefail
# set -x  # Enable debug tracing

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# =============================================================================
# DEFAULT CONFIGURATION
# =============================================================================

create_default_config() {
    cat << 'CONFIG_EOF'
#!/data/data/com.termux/files/usr/bin/bash
# config.sh - Configuration for voice coding assistant

# Development machine connection
DEV_HOST="user@your-dev-machine.local"
SSH_KEY="$HOME/.ssh/termux_coding"
CLAUDE="/home/pepijn/.local/bin/claude"
DEV_CWD="~"  # Working directory on dev machine

# Voice processing options
USE_LOCAL_STT=true    # whisper.cpp vs OpenAI API
USE_LOCAL_TTS=true    # termux-tts-speak vs OpenAI TTS

# OpenAI API (if using cloud options)
OPENAI_API_KEY="${OPENAI_API_KEY:-}"

# Whisper settings (if using local STT)
WHISPER_MODEL="base"  # Options: tiny, base, small, medium, large
WHISPER_LANGUAGE="en"

# TTS settings (if using local TTS)
TTS_PITCH="1.0"  # 1.0 is normal pitch, lower = deeper, higher = higher
TTS_RATE="1.0"   # 1.0 is normal speed, lower = slower, higher = faster

# File locations
TEMP_DIR="${TMPDIR:-$HOME/.voice_coding_temp}"
AUDIO_FILE="$TEMP_DIR/recording.m4a"
TRANSCRIPTION_FILE="$TEMP_DIR/transcription.txt"
RESPONSE_FILE="$TEMP_DIR/claude_response.json"
TTS_FILE="$TEMP_DIR/tts_output.mp3"

# Ensure temp directory exists
mkdir -p "$TEMP_DIR"
CONFIG_EOF
}

# Load configuration - use config.sh if it exists, otherwise create from defaults
load_config() {
    if [[ -f "$SCRIPT_DIR/config.sh" ]]; then
        source "$SCRIPT_DIR/config.sh"
    else
        # Create temporary config and source it
        eval "$(create_default_config)"
    fi
}

# Load configuration
load_config

# =============================================================================
# AUDIO FUNCTIONS
# =============================================================================

# Record audio with user control
record_audio() {
    local status_msg="🎤 Recording... (press any key to stop)"
    echo "$status_msg"
    
    # Remove existing audio file if it exists
    rm -f "$AUDIO_FILE"
    
    # Start recording (non-blocking, no limit) with AAC encoder for better compatibility
    # Note: termux-microphone-record defaults to AAC encoder which creates m4a format
    termux-microphone-record -f "$AUDIO_FILE" -l 0 -e aac
    
    # Wait for user input (no timeout)
    read -n1
    # User stopped recording
    termux-microphone-record -q
    echo "✅ Recording stopped by user"
    
    # Check if recording file exists and has content
    if [[ -f "$AUDIO_FILE" && -s "$AUDIO_FILE" ]]; then
        return 0
    else
        echo "❌ Recording failed or empty"
        return 1
    fi
}

# Convert speech to text
speech_to_text() {
    if $USE_LOCAL_STT; then
        local_speech_to_text
    else
        api_speech_to_text
    fi
}

# Local speech recognition using whisper.cpp
local_speech_to_text() {
    echo "🧠 Transcribing locally..." >&2
    
    # Run whisper.cpp (adjust path as needed)
    if command -v whisper >/dev/null; then
        whisper "$AUDIO_FILE" \
            --model "$WHISPER_MODEL" \
            --language "$WHISPER_LANGUAGE" \
            --output-txt \
            --output-dir "$TEMP_DIR" \
            --output-file "transcription" 2>/dev/null
        
        if [[ -f "$TRANSCRIPTION_FILE" ]]; then
            cat "$TRANSCRIPTION_FILE"
            return 0
        fi
    fi
    
    echo "❌ Local transcription failed" >&2
    return 1
}

# API-based speech recognition
api_speech_to_text() {
    echo "🌐 Transcribing via API..." >&2
    
    if [[ -z "$OPENAI_API_KEY" ]]; then
        echo "❌ OpenAI API key not set" >&2
        return 1
    fi
    
    # Debug: Check file before uploading
    if [[ -f "$AUDIO_FILE" ]]; then
        local file_size=$(stat -c%s "$AUDIO_FILE" 2>/dev/null)
        local file_type=$(file -b "$AUDIO_FILE" 2>/dev/null)
        echo "Debug: File size: ${file_size} bytes, Type: ${file_type}" >&2
    else
        echo "❌ Audio file does not exist: $AUDIO_FILE" >&2
        return 1
    fi
    
    local response
    response=$(curl -s -X POST "https://api.openai.com/v1/audio/transcriptions" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -F "file=@$AUDIO_FILE" \
        -F "model=whisper-1")
    
    if [[ $? -eq 0 ]]; then
        local transcribed_text
        transcribed_text=$(echo "$response" | jq -r '.text // empty')
        
        if [[ -z "$transcribed_text" || "$transcribed_text" == "null" ]]; then
            echo "❌ API returned empty transcription" >&2
            echo "Response: $response" >&2
            return 1
        fi
        
        echo "$transcribed_text"
        return 0
    else
        echo "❌ API transcription failed" >&2
        echo "Response: $response" >&2
        return 1
    fi
}

# Convert text to speech
text_to_speech() {
    local text="$1"
    [[ -z "$text" ]] && return 1
    
    if $USE_LOCAL_TTS; then
        local_text_to_speech "$text"
    else
        api_text_to_speech "$text"
    fi
}

# Local text-to-speech using termux-tts-speak
local_text_to_speech() {
    local text="$1"
    echo "🔊 Speaking locally..." >&2
    
    termux-tts-speak -p "$TTS_PITCH" -r "$TTS_RATE" "$text"
}

# API-based text-to-speech
api_text_to_speech() {
    local text="$1"
    echo "🌐 Generating speech via API..." >&2
    
    if [[ -z "$OPENAI_API_KEY" ]]; then
        echo "❌ OpenAI API key not set" >&2
        return 1
    fi
    
    curl -s -X POST "https://api.openai.com/v1/audio/speech" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"tts-1\",
            \"input\": \"$text\",
            \"voice\": \"nova\"
        }" \
        --output "$TTS_FILE"
    
    if [[ -f "$TTS_FILE" && -s "$TTS_FILE" ]]; then
        termux-media-player play "$TTS_FILE"
        return 0
    else
        echo "❌ API TTS failed" >&2
        return 1
    fi
}

# Test audio functionality
test_audio() {
    echo "🧪 Testing audio functionality..."
    
    # Test TTS
    echo "Testing text-to-speech..."
    text_to_speech "Audio test successful. The voice coding assistant is working."
    
    echo "Press any key to test recording..."
    read -n1
    
    # Test recording and transcription
    if record_audio; then
        local transcription
        if transcription=$(speech_to_text); then
            if [[ -n "$transcription" ]]; then
                echo "Transcription: $transcription"
                text_to_speech "I heard you say: $transcription"
            else
                echo "❌ Transcription failed - empty result"
            fi
        else
            echo "❌ Transcription failed"
        fi
    else
        echo "❌ Recording failed"
    fi
}

# =============================================================================
# CLAUDE INTEGRATION FUNCTIONS
# =============================================================================

# Check SSH connection to development machine
check_dev_connection() {
    echo "🔌 Checking connection to development machine..."
    
    if ssh -i "$SSH_KEY" -o ConnectTimeout=5 "$DEV_HOST" "echo 'Connection OK'" >/dev/null 2>&1; then
        echo "✅ Connected to $DEV_HOST"
        return 0
    else
        echo "❌ Cannot connect to $DEV_HOST"
        echo "Check SSH configuration and network connectivity"
        return 1
    fi
}

# Install mobile-voice-coding output style on development machine
install_output_style() {
    echo "📋 Installing mobile-voice-coding output style..."
    
    # Create the output style content
    local output_style_content
    output_style_content=$(cat << 'STYLE_EOF'
---
description: Voice-first mobile coding assistant for Termux with speech-friendly responses and clear before/after code examples
---

You are a voice coding assistant on Termux mobile terminal. User speaks requests that get transcribed and sent via SSH. Your response is read aloud (except code blocks) then displayed visually. User has no code editor so you must describe changes clearly.

## SPEECH-OPTIMIZED GUIDELINES:

- NO MARKDOWN in speech portions - no asterisks, hashtags, bullets, bold, italic, underlines, or any formatting
- Use brief conversational text that sounds natural when spoken aloud
- Put ALL code blocks at the VERY END with proper markdown fences and language IDs
- Before any code block, provide a clear description of what the code does
- Keep it brief, but not at the cost of clarity
- Break complex tasks into small voice-friendly steps
- Focus each interaction on ONE specific change

## TWO OPERATION MODES:

**PLAN MODE** (analyze and propose without making changes):
- Show current code state
- Propose one small specific change
- Ask for confirmation before proceeding
- Explain the reasoning in conversational terms

**EDIT MODE** (implement changes directly):
- Make the single requested change using tools
- Briefly explain what was changed in human terms
- Show the updated code at the end

## RESPONSE STRUCTURE:

1. **Spoken explanation** (conversational, no markdown)
2. **Code blocks** (at the very end, properly formatted)

## EXAMPLE INTERACTIONS:

**Plan Mode Response:**
"I found the login function in auth dot js on line 45. Right now it only checks if the username exists but completely ignores the password parameter. It just returns true whenever it finds a valid username. I can add a simple password comparison right after the username check. Should I proceed with this change?"

```js
function login(username, password) {
    if (validateUser(username)) {
        return true;  // ignores password completely
    }
    return false;
}
```

**Edit Mode Response:**
"I added the password validation after the username check. Now both the username and password must be correct to return true. The function will only succeed when both validations pass."

```js
function login(username, password) {
    if (validateUser(username) && password === "secret123") {
        return true;
    }
    return false;
}
```

## ADDITIONAL REQUIREMENTS:

- If transcription is unclear, say "Could you repeat that? I heard X but want to make sure"
- Always show before and after code when making changes
- Use tools appropriately for software engineering tasks - read files before editing, validate syntax, run tests when available
- Break large refactors into multiple small voice interactions
- Explain file structure and navigation when user asks about project layout
- Remember this is mobile coding - keep it brief and focused

STYLE_EOF
)
    
    # Upload and install the output style
    ssh -i "$SSH_KEY" "$DEV_HOST" "mkdir -p ~/.claude/output-styles && cat > ~/.claude/output-styles/mobile-voice-coding.md" <<< "$output_style_content"
    
    if [[ $? -eq 0 ]]; then
        echo "✅ Mobile-voice-coding output style installed"
        return 0
    else
        echo "❌ Failed to install output style"
        return 1
    fi
}

# Test Claude Code availability
test_claude_code() {
    echo "🧪 Testing Claude Code on development machine..."
    
    local test_response
    test_response=$(ssh -i "$SSH_KEY" "$DEV_HOST" \
        "cd $DEV_CWD && $CLAUDE -p 'Say hello and confirm you can help with coding' --output-format json" < /dev/null 2>/dev/null)
    
    if [[ $? -eq 0 && -n "$test_response" ]]; then
        echo "✅ Claude Code is working"
        
        # Extract text from Claude Code SDK response format
        local text_content
        text_content=$(echo "$test_response" | jq -r '.result // empty' 2>/dev/null)
        
        if [[ -n "$text_content" && "$text_content" != "null" ]]; then
            echo "Response: $(echo "$text_content" | head -c 100)..."
        else
            echo "Could not extract text from response"
        fi
        return 0
    else
        echo "❌ Claude Code test failed"
        return 1
    fi
}

# Send prompt to Claude and get structured response
query_claude() {
    local prompt="$1"
    [[ -z "$prompt" ]] && return 1
    
    echo "🤖 Querying Claude Code..." >&2
    
    # Escape quotes in prompt for SSH command
    local escaped_prompt
    escaped_prompt=$(printf '%q' "$prompt")
    
    # Use mobile-voice-coding output style for voice coding context
    local claude_response
    local claude_command
    local settings_json='{"outputStyle": "mobile-voice-coding"}'
    
    # Determine if we should start a new session or resume existing one
    if [[ -z "$CLAUDE_SESSION_ID" ]]; then
        # First call - start new session and capture session ID
        claude_command="cd $DEV_CWD && $CLAUDE --print $escaped_prompt --permission-mode $PERMISSION_MODE --output-format json --settings '$settings_json'"
    else
        # Subsequent calls - resume existing session
        claude_command="cd $DEV_CWD && $CLAUDE --print $escaped_prompt --resume '$CLAUDE_SESSION_ID' --permission-mode $PERMISSION_MODE --output-format json --settings '$settings_json'"
    fi
    
    claude_response=$(ssh -i "$SSH_KEY" "$DEV_HOST" "$claude_command" < /dev/null 2>/dev/null)
    
    if [[ $? -eq 0 && -n "$claude_response" ]]; then
        echo "$claude_response" > "$RESPONSE_FILE"
        
        # Extract session ID from response if this was the first call
        if [[ -z "$CLAUDE_SESSION_ID" ]]; then
            local session_id
            session_id=$(echo "$claude_response" | jq -r '.session_id // empty' 2>/dev/null)
            if [[ -n "$session_id" && "$session_id" != "null" ]]; then
                CLAUDE_SESSION_ID="$session_id"
                echo "📝 Session ID captured: $CLAUDE_SESSION_ID" >&2
            fi
        fi
        
        return 0
    else
        echo "❌ Claude query failed" >&2
        return 1
    fi
}

# Global variables for parsed content
FULL_CONTENT=""
TTS_CONTENT=""

# Parse Claude response and extract different content types
parse_claude_response() {
    [[ ! -f "$RESPONSE_FILE" ]] && return 1
    
    # Extract full text content from Claude Code SDK format (with code blocks for display)
    FULL_CONTENT=$(jq -r '.result // empty' "$RESPONSE_FILE" 2>/dev/null)
    
    # Create TTS version with code blocks removed and markdown filtered
    TTS_CONTENT=$(echo "$FULL_CONTENT" | \
        # Remove code blocks (```...```)
        sed '/```/,/```/d' | \
        # Remove bold (**text** -> text)
        sed 's/\*\*\([^*]*\)\*\*/\1/g' | \
        # Remove italic (*text* -> text)
        sed 's/\*\([^*]*\)\*/\1/g' | \
        # Remove bold (__text__ -> text)
        sed 's/__\([^_]*\)__/\1/g' | \
        # Remove italic (_text_ -> text)
        sed 's/_\([^_]*\)_/\1/g' | \
        # Remove strikethrough (~~text~~ -> text)
        sed 's/~~\([^~]*\)~~/\1/g' | \
        # Remove headers (### Header -> Header)
        sed 's/^#\+[ ]*//' | \
        # Remove bullet points (- item -> item)
        sed 's/^[-*+][ ]*//' | \
        # Remove inline code (`code` -> code)
        sed 's/`\([^`]*\)`/\1/g' \
        2>/dev/null || echo "$FULL_CONTENT")
}

# Display response using bat for markdown formatting
display_response() {
    local content="$1"
    [[ -z "$content" ]] && return 1
    
    echo "💬 Claude's response:"
    echo "────────────────────"
    
    # Use bat for markdown rendering if available
    if command -v bat >/dev/null; then
        echo "$content" | bat --language=markdown --style=plain --theme=ansi --paging=never
    else
        echo "$content"
    fi
    echo "────────────────────"
}

# Complete Claude interaction workflow
process_with_claude() {
    local user_input="$1"
    [[ -z "$user_input" ]] && return 1
    
    # Query Claude
    if ! query_claude "$user_input"; then
        return 1
    fi
    
    # Parse response (populates global FULL_CONTENT and TTS_CONTENT)
    if ! parse_claude_response; then
        return 1
    fi
    
    # Display full response with bat markdown formatting
    if [[ -n "$FULL_CONTENT" ]]; then
        display_response "$FULL_CONTENT"
        echo
        
        # Speak the TTS version (without code blocks)
        if [[ -n "$TTS_CONTENT" ]]; then
            text_to_speech "$TTS_CONTENT" &
        fi
    fi
    
    return 0
}

# =============================================================================
# TUI FUNCTIONS
# =============================================================================

# Global state
CLAUDE_SESSION_ID=""
PERMISSION_MODE="plan"  # Can be: plan, acceptEdits

# Terminal control functions (simplified)
hide_cursor() { printf '\e[?25l'; }
show_cursor() { printf '\e[?25h'; }

# Status indicators
get_connection_status() {
    if ssh -i "$SSH_KEY" -o ConnectTimeout=2 "$DEV_HOST" "echo ok" >/dev/null 2>&1; then
        echo "🟢 Connected"
    else
        echo "🔴 Disconnected"
    fi
}

get_audio_status() {
    local stt_status="$([ "$USE_LOCAL_STT" = true ] && echo "Local" || echo "API")"
    local tts_status="$([ "$USE_LOCAL_TTS" = true ] && echo "Local" || echo "API")"
    echo "🎤 STT: $stt_status | 🔊 TTS: $tts_status"
}

get_session_status() {
    if [[ -n "$CLAUDE_SESSION_ID" ]]; then
        echo "📝 Session: ${CLAUDE_SESSION_ID:0:8}..."
    else
        echo "📝 Session: New"
    fi
}

get_mode_status() {
    case "$PERMISSION_MODE" in
        "plan")
            echo "🎯 Mode: Plan"
            ;;
        "acceptEdits")
            echo "✏️  Mode: Edit"
            ;;
        *)
            echo "🎯 Mode: Plan"
            ;;
    esac
}

# Simple status line display
show_status() {
    local connection_status
    connection_status=$(get_connection_status)
    
    local session_status
    session_status=$(get_session_status)
    
    local mode_status
    mode_status=$(get_mode_status)
    
    echo "Voice Coding Assistant | $connection_status | $session_status | $mode_status | [SPACE=record C=cd M=mode R=reset S=ssh Q=quit]"
}



# Main voice interaction
handle_voice_command() {
    echo "🎙️ Starting voice interaction..."
    
    # Record audio
    if ! record_audio; then
        echo "❌ Recording failed"
        return 1
    fi
    
    # Transcribe
    local transcription
    if ! transcription=$(speech_to_text); then
        echo "❌ Transcription failed"
        return 1
    fi
    
    if [[ -z "$transcription" ]]; then
        echo "❌ Transcription failed - empty result"
        return 1
    fi
    
    echo "📝 You said: $transcription"
    
    # Process with Claude
    if ! process_with_claude "$transcription"; then
        echo "❌ Claude processing failed"
        text_to_speech "Sorry, I couldn't process your request. Please check the connection and try again."
    fi
}

# Reset Claude session
reset_claude_session() {
    CLAUDE_SESSION_ID=""
    echo "🔄 Claude session reset" >&2
}

# Cycle through permission modes
cycle_permission_mode() {
    case "$PERMISSION_MODE" in
        "plan")
            PERMISSION_MODE="acceptEdits"
            echo "✏️  Switched to ACCEPT EDITS mode - Claude will implement changes" >&2
            ;;
        "acceptEdits")
            PERMISSION_MODE="plan"
            echo "🎯 Switched to PLAN mode - Claude will analyze and propose changes" >&2
            ;;
        *)
            PERMISSION_MODE="plan"
            echo "🎯 Reset to PLAN mode" >&2
            ;;
    esac
    
}

# Change working directory on dev machine
change_directory() {
    echo "📁 Current directory: $DEV_CWD"
    read -p "Enter new directory path (or press Enter to cancel): " new_dir
    
    if [[ -z "$new_dir" ]]; then
        echo "Directory change cancelled"
        return
    fi
    
    # Test if directory exists on dev machine
    echo "Testing directory access..."
    if ssh -i "$SSH_KEY" "$DEV_HOST" "test -d '$new_dir'" >/dev/null 2>&1; then
        # Update DEV_CWD in memory
        DEV_CWD="$new_dir"
        
        # Update config file
        sed -i "s|DEV_CWD=.*|DEV_CWD=\"$new_dir\"|" "$SCRIPT_DIR/config.sh" 2>/dev/null || true
        
        echo "✅ Changed directory to: $new_dir"
        
        # Reset session since we changed directories
        reset_claude_session
        echo "🔄 Session reset due to directory change"
    else
        echo "❌ Directory '$new_dir' does not exist or is not accessible"
    fi
}

# SSH into development machine
ssh_to_dev() {
    echo "🔗 Opening SSH connection to development machine..."
    echo "📁 Working directory: $DEV_CWD"
    echo "🖥️  Host: $DEV_HOST"
    echo
    echo "Press Ctrl+D or type 'exit' to return to voice assistant"
    echo "────────────────────────────────────────────────────────────"
    
    # Open interactive SSH session with automatic directory change
    ssh -i "$SSH_KEY" -t "$DEV_HOST" "cd '$DEV_CWD' && exec \$SHELL -l"
    
    echo "────────────────────────────────────────────────────────────"
    echo "🔙 Returned to voice coding assistant"
}

# Cleanup on exit
cleanup() {
    show_cursor
    #clear_screen
    echo "👋 Voice coding assistant closed"
    
    # Clean up temp files
    rm -f "$AUDIO_FILE" "$TRANSCRIPTION_FILE" "$RESPONSE_FILE" "$TTS_FILE"
    
    # Reset session for next run
    reset_claude_session
    exit 0
}

# Main simplified loop
main_loop() {
    # Setup
    trap cleanup INT TERM EXIT
    
    # Initial connection check
    if ! check_dev_connection; then
        echo "❌ Cannot start without development machine connection"
        exit 1
    fi
    
    # Main loop
    while true; do
        show_status
        
        # Read user input (silent mode)
        read -s -n1
        case $REPLY in
            ' ')  handle_voice_command || true ;;
            'c')  change_directory || true ;;
            'm')  cycle_permission_mode || true ;;
            'r')  reset_claude_session || true ;;
            's')  ssh_to_dev || true ;;
            'q')  break ;;
            *)    
                echo "Unknown command: '$REPLY' (Use SPACE, C, M, R, S, or Q)"
                ;;
        esac
    done
}

# =============================================================================
# MAIN SCRIPT FUNCTIONS
# =============================================================================

# Help text
show_help() {
    cat << EOF
Voice Coding Assistant for Termux

USAGE:
  $0 [COMMAND]

COMMANDS:
  start      Start the voice coding assistant (default)
  install    Install required packages
  test       Test audio and connection functionality
  setup      Interactive setup wizard
  help       Show this help message

INTERACTIVE COMMANDS (during voice session):
  SPACE      Record and process voice command
  C          Change working directory on dev machine
  M          Cycle between Plan mode (analyze/propose) and Edit mode (implement)
  R          Reset Claude session
  S          SSH into development machine for manual tasks
  Q          Quit application

DEVELOPMENT MODES:
  Plan Mode  Claude analyzes code and proposes changes without implementing
  Edit Mode  Claude implements changes directly using available tools

EXAMPLES:
  $0                    # Start the assistant
  $0 test              # Test functionality
  $0 setup             # Run setup wizard

REQUIREMENTS:
  - Termux with termux-api package
  - SSH access to development machine with Claude Code
  - Microphone permissions granted
  - Optional: OpenAI API key for higher quality audio

EOF
}

# Install required packages
install_packages() {
    echo "📦 Installing required packages..."
    
    # Update package lists
    echo "Updating package lists..."
    pkg update
    
    # Install all essential packages in one command
    echo "Installing packages: openssh, jq, curl, termux-api, nano, bat..."
    pkg install -y openssh jq curl termux-api nano bat
    
    # Check if Termux:API app is installed
    echo
    echo "⚠️  Important: Make sure you have installed the Termux:API app from F-Droid"
    echo "   and granted microphone permissions in Android settings."
    echo
    read -p "Press Enter when ready to continue..."
}

# Interactive setup wizard
setup_wizard() {
    echo "🚀 Voice Coding Assistant Setup Wizard"
    echo "======================================="
    echo
    
    # Package installation
    echo "0. Package Installation"
    read -p "Install required packages? (y/n): " install_pkgs
    if [[ "$install_pkgs" =~ ^[Yy]$ ]]; then
        install_packages
    fi
    echo
    
    # Create config from template if it doesn't exist
    if [[ ! -f "$SCRIPT_DIR/config.sh" ]]; then
        echo "Creating config from template..."
        create_default_config > "$SCRIPT_DIR/config.sh"
        chmod +x "$SCRIPT_DIR/config.sh"
    fi
    
    # Re-load configuration
    load_config
    
    # Development machine setup
    echo "1. SSH Key Generation"
    ssh_key="$HOME/.ssh/termux_coding"
    
    if [[ ! -f "$ssh_key" ]]; then
        echo "Generating SSH key pair..."
        mkdir -p "$HOME/.ssh"
        ssh-keygen -t ed25519 -f "$ssh_key" -N "" -C "termux-voice-coding"
        chmod 600 "$ssh_key"
        chmod 644 "$ssh_key.pub"
    else
        echo "SSH key already exists at $ssh_key"
    fi
    
    echo
    echo "📋 Run this command on your development machine:"
    echo "────────────────────────────────────────────────────"
    echo "echo '$(cat "$ssh_key.pub")' >> ~/.ssh/authorized_keys"
    echo "────────────────────────────────────────────────────"
    echo
    read -p "Press Enter when done..."
    
    echo
    echo "2. Development Machine Configuration"
    echo "Enter your development machine SSH details:"
    
    read -p "Host (current: $DEV_HOST): " dev_host
    dev_host=${dev_host:-"$DEV_HOST"}
    
    read -p "Claude path (current: $CLAUDE): " claude_path
    claude_path=${claude_path:-"$CLAUDE"}
    
    read -p "Working directory (current: $DEV_CWD): " dev_cwd
    dev_cwd=${dev_cwd:-"$DEV_CWD"}
    
    # Update config
    sed -i "s|DEV_HOST=.*|DEV_HOST=\"$dev_host\"|" "$SCRIPT_DIR/config.sh"
    sed -i "s|SSH_KEY=.*|SSH_KEY=\"$ssh_key\"|" "$SCRIPT_DIR/config.sh"
    sed -i "s|CLAUDE=.*|CLAUDE=\"$claude_path\"|" "$SCRIPT_DIR/config.sh"
    sed -i "s|DEV_CWD=.*|DEV_CWD=\"$dev_cwd\"|" "$SCRIPT_DIR/config.sh"
    
    # Re-source the updated config
    load_config
    
    echo
    echo "3. Audio Preferences"
    
    # Speech-to-Text settings
    echo "3a. Speech-to-Text (STT) Settings"
    if [[ "$USE_LOCAL_STT" == "true" ]]; then
        current_stt="1 (Local)"
    else
        current_stt="2 (API)"
    fi
    
    echo "Choose speech-to-text processing:"
    echo "  1) Local processing (whisper.cpp, offline, private)"
    echo "  2) API processing (OpenAI Whisper, higher quality, requires internet)"
    read -p "STT Selection (current: $current_stt): " stt_choice
    
    case $stt_choice in
        1)
            sed -i "s|USE_LOCAL_STT=.*|USE_LOCAL_STT=true|" "$SCRIPT_DIR/config.sh"
            ;;
        2)
            sed -i "s|USE_LOCAL_STT=.*|USE_LOCAL_STT=false|" "$SCRIPT_DIR/config.sh"
            ;;
        "")
            echo "Keeping current STT setting"
            ;;
        *)
            echo "Invalid selection, keeping current STT setting"
            ;;
    esac
    
    echo
    echo "3b. Text-to-Speech (TTS) Settings"
    if [[ "$USE_LOCAL_TTS" == "true" ]]; then
        current_tts="1 (Local)"
    else
        current_tts="2 (API)"
    fi
    
    echo "Choose text-to-speech processing:"
    echo "  1) Local processing (termux-tts-speak, offline, uses Android TTS)"
    echo "  2) API processing (OpenAI TTS, higher quality, requires internet)"
    read -p "TTS Selection (current: $current_tts): " tts_choice
    
    case $tts_choice in
        1)
            sed -i "s|USE_LOCAL_TTS=.*|USE_LOCAL_TTS=true|" "$SCRIPT_DIR/config.sh"
            ;;
        2)
            sed -i "s|USE_LOCAL_TTS=.*|USE_LOCAL_TTS=false|" "$SCRIPT_DIR/config.sh"
            ;;
        "")
            echo "Keeping current TTS setting"
            ;;
        *)
            echo "Invalid selection, keeping current TTS setting"
            ;;
    esac
    
    # Check if API key is needed
    load_config  # Reload to get updated settings
    if [[ "$USE_LOCAL_STT" == "false" || "$USE_LOCAL_TTS" == "false" ]]; then
        echo
        echo "OpenAI API key required for API processing:"
        read -p "Enter OpenAI API key (or press Enter to skip): " api_key
        if [[ -n "$api_key" ]]; then
            echo "export OPENAI_API_KEY='$api_key'" >> ~/.bashrc
            echo "API key added to ~/.bashrc"
        else
            echo "⚠️  No API key provided. API processing will fail without it."
        fi
    fi
    
    echo
    echo "4. Output Style Installation"
    read -p "Install mobile-voice-coding output style on dev machine? (y/n): " install_style
    if [[ "$install_style" =~ ^[Yy]$ ]]; then
        if ! install_output_style; then
            echo "⚠️  Output style installation failed, will use default prompting"
        fi
    else
        echo "Skipping output style installation - will use system prompts"
    fi
    
    echo
    echo "5. Testing Setup"
    if test_setup; then
        echo "✅ Setup completed successfully!"
        echo "Run '$0 start' to begin voice coding"
    else
        echo "❌ Setup test failed. Please check configuration."
    fi
}

# Test setup functionality
test_setup() {
    echo "🧪 Testing setup..."
    
    # Test SSH connection
    if ! check_dev_connection; then
        return 1
    fi
    
    # Test Claude Code
    if ! test_claude_code; then
        return 1
    fi
    
    # Test audio functionality
    echo "Testing audio functionality..."
    test_audio
    
    return 0
}


# Main entry point
main() {
    case "${1:-start}" in
        start)
            echo "🎙️ Starting Voice Coding Assistant..."
            main_loop
            ;;
        install)
            install_packages
            ;;
        test)
            test_setup
            ;;
        setup)
            setup_wizard
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"