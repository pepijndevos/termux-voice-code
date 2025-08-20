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

# File locations
TEMP_DIR="${TMPDIR:-$HOME/.voice_coding_temp}"
AUDIO_FILE="$TEMP_DIR/recording.wav"
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
    
    # Start recording (non-blocking, no limit)
    termux-microphone-record -f "$AUDIO_FILE" -l 0
    
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
    
    local response
    response=$(curl -s -X POST "https://api.openai.com/v1/audio/transcriptions" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -F "file=@$AUDIO_FILE" \
        -F "model=whisper-1")
    
    if [[ $? -eq 0 ]]; then
        echo "$response" | jq -r '.text // empty'
        return 0
    else
        echo "❌ API transcription failed" >&2
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
    
    termux-tts-speak "$text"
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
        transcription=$(speech_to_text)
        if [[ -n "$transcription" ]]; then
            echo "Transcription: $transcription"
            text_to_speech "I heard you say: $transcription"
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
    
    # Execute Claude Code on development machine
    local claude_response
    claude_response=$(ssh -i "$SSH_KEY" "$DEV_HOST" \
        "cd $DEV_CWD && $CLAUDE -p $escaped_prompt --output-format json" < /dev/null 2>/dev/null)
    
    if [[ $? -eq 0 && -n "$claude_response" ]]; then
        echo "$claude_response" > "$RESPONSE_FILE"
        return 0
    else
        echo "❌ Claude query failed" >&2
        return 1
    fi
}

# Parse Claude response and extract different content types
parse_claude_response() {
    [[ ! -f "$RESPONSE_FILE" ]] && return 1
    
    # Extract text content from Claude Code SDK format
    local text_content
    text_content=$(jq -r '.result // empty' "$RESPONSE_FILE" 2>/dev/null)
    
    # Extract code blocks from markdown text (simple extraction)
    local code_content
    code_content=$(echo "$text_content" | sed -n '/```/,/```/p' | sed '1d;$d' 2>/dev/null || echo "")
    
    # Extract cost information
    local cost
    cost=$(jq -r '.total_cost_usd // "N/A"' "$RESPONSE_FILE" 2>/dev/null)
    
    # Return structured data
    cat << EOF
TEXT_CONTENT<<ENDTEXT
$text_content
ENDTEXT
CODE_CONTENT<<ENDCODE
$code_content
ENDCODE
COST<<ENDCOST
$cost
ENDCOST
EOF
}

# Display code with syntax highlighting (if available)
display_code() {
    local code_text="$1"
    [[ -z "$code_text" ]] && return 1
    
    echo "📄 Code:"
    echo "────────────────────"
    
    # Use bat for syntax highlighting if available
    if command -v bat >/dev/null; then
        echo "$code_text" | bat --style=numbers --theme=ansi
    else
        echo "$code_text"
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
    
    # Parse response
    local parsed_response
    parsed_response=$(parse_claude_response)
    
    # Extract components
    local text_content
    text_content=$(echo "$parsed_response" | sed -n '/TEXT_CONTENT<<ENDTEXT/,/ENDTEXT/p' | sed '1d;$d')
    
    local code_content
    code_content=$(echo "$parsed_response" | sed -n '/CODE_CONTENT<<ENDCODE/,/ENDCODE/p' | sed '1d;$d')
    
    local cost
    cost=$(echo "$parsed_response" | sed -n '/COST<<ENDCOST/,/ENDCOST/p' | sed '1d;$d')
    
    # Display results
    if [[ -n "$text_content" ]]; then
        echo "💬 Claude's response:"
        echo "$text_content"
        echo
        
        # Speak the response
        text_to_speech "$text_content" &
    fi
    
    if [[ -n "$code_content" && "$code_content" != "null" ]]; then
        display_code "$code_content"
    fi
    
    if [[ -n "$cost" && "$cost" != "N/A" ]]; then
        echo "💰 Cost: \$$cost"
    fi
    
    return 0
}

# =============================================================================
# TUI FUNCTIONS
# =============================================================================

# Global state
CONVERSATION_HISTORY=()
LAST_TRANSCRIPTION=""
LAST_RESPONSE=""

# Terminal control functions
hide_cursor() { printf '\e[?25l'; }
show_cursor() { printf '\e[?25h'; }
clear_screen() { printf '\e[2J\e[H'; }
move_cursor() { printf '\e[%d;%dH' "$1" "$2"; }

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
    echo "🎤 $stt_status | 🔊 $tts_status"
}

# Main TUI display
draw_interface() {
    clear_screen
    hide_cursor
    
    local connection_status
    connection_status=$(get_connection_status)
    
    local audio_status
    audio_status=$(get_audio_status)
    
    echo "┌──────────────────────────────────────────┐"
    echo "│           Voice Coding Assistant         │"
    echo "├──────────────────────────────────────────┤"
    echo "│ Status: $connection_status"
    echo "│ Audio:  $audio_status"
    echo "├──────────────────────────────────────────┤"
    echo "│ Controls:                                |"
    echo "│ SPACE = Record Voice Command             |"
    echo "│ T = Toggle TTS | S = Toggle STT          |" 
    echo "│ H = History | R = Test | Q = Quit        |"
    echo "└──────────────────────────────────────────┘"
    echo
    
    # Recent interaction
    if [[ -n "$LAST_TRANSCRIPTION" ]]; then
        echo "📝 Last transcription:"
        echo "   $LAST_TRANSCRIPTION"
        echo
    fi
    
    if [[ -n "$LAST_RESPONSE" ]]; then
        echo "🤖 Last response:"
        echo "   $(echo "$LAST_RESPONSE" | head -c 200)..."
        echo
    fi
    
    echo "Press any key for command..."
    show_cursor
}

# Show conversation history
show_history() {
    clear_screen
    echo "📜 Conversation History"
    echo "════════════════════════"
    
    if [[ ${#CONVERSATION_HISTORY[@]} -eq 0 ]]; then
        echo "No conversation history yet."
    else
        local i=1
        for entry in "${CONVERSATION_HISTORY[@]}"; do
            echo "$i. $entry"
            echo "────────────────────────"
            ((i++))
        done
    fi
    
    echo
    echo "Press any key to return..."
    read -n1
}

# Toggle settings
toggle_tts() {
    if $USE_LOCAL_TTS; then
        USE_LOCAL_TTS=false
        echo "🔊 Switched to API TTS"
    else
        USE_LOCAL_TTS=true
        echo "🔊 Switched to Local TTS"
    fi
    sleep 1
}

toggle_stt() {
    if $USE_LOCAL_STT; then
        USE_LOCAL_STT=false
        echo "🎤 Switched to API STT"
    else
        USE_LOCAL_STT=true
        echo "🎤 Switched to Local STT"
    fi
    sleep 1
}

# Main voice interaction
handle_voice_command() {
    echo "🎙️ Starting voice interaction..."
    
    # Record audio
    if ! record_audio; then
        echo "❌ Recording failed"
        sleep 2
        return 1
    fi
    
    # Transcribe
    local transcription
    transcription=$(speech_to_text)
    
    if [[ -z "$transcription" ]]; then
        echo "❌ Transcription failed"
        sleep 2
        return 1
    fi
    
    LAST_TRANSCRIPTION="$transcription"
    echo "📝 You said: $transcription"
    
    # Process with Claude
    if process_with_claude "$transcription"; then
        # Extract text response for history
        if [[ -f "$RESPONSE_FILE" ]]; then
            LAST_RESPONSE=$(jq -r '.result // empty' "$RESPONSE_FILE" 2>/dev/null)
            CONVERSATION_HISTORY+=("You: $transcription")
            CONVERSATION_HISTORY+=("Claude: $LAST_RESPONSE")
        fi
    else
        echo "❌ Claude processing failed"
        text_to_speech "Sorry, I couldn't process your request. Please check the connection and try again."
    fi
    
    echo
    echo "Press any key to continue..."
    read -n1
}

# Cleanup on exit
cleanup() {
    show_cursor
    #clear_screen
    echo "👋 Voice coding assistant closed"
    
    # Clean up temp files
    rm -f "$AUDIO_FILE" "$TRANSCRIPTION_FILE" "$RESPONSE_FILE" "$TTS_FILE"
    exit 0
}

# Main TUI loop
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
        draw_interface
        
        # Read user input
        read -n1
        case $REPLY in
            ' ')  handle_voice_command ;;
            't')  toggle_tts ;;
            's')  toggle_stt ;;
            'h')  show_history ;;
            'r')  test_audio ;;
            'q')  break ;;
            *)    
                echo "Unknown command: '$REPLY'"
                sleep 1 
                ;;
        esac
    done
    
    cleanup
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
  config     Edit configuration
  help       Show this help message

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
    
    # Essential packages
    local packages=(
        "openssh"      # SSH client for dev machine connection
        "jq"           # JSON parsing for Claude responses
        "curl"         # API calls for OpenAI
        "termux-api"   # Audio recording and TTS
        "nano"         # Basic editor
    )
    
    for package in "${packages[@]}"; do
        if ! command -v "$package" >/dev/null 2>&1; then
            echo "Installing $package..."
            pkg install -y "$package"
        else
            echo "✅ $package already installed"
        fi
    done
    
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
    echo "📋 Copy this public key to your development machine:"
    echo "────────────────────────────────────────────────────"
    cat "$ssh_key.pub"
    echo "────────────────────────────────────────────────────"
    echo
    echo "Add it to ~/.ssh/authorized_keys on your dev machine"
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
    
    # Show current audio settings
    if [[ "$USE_LOCAL_STT" == "true" ]]; then
        current_choice="1 (Local)"
    else
        current_choice="2 (API)"
    fi
    
    echo "Choose your preferred audio processing:"
    echo "  1) Local processing (offline, private)"
    echo "  2) API processing (higher quality, requires internet)"
    read -p "Selection (current: $current_choice): " audio_choice
    
    case $audio_choice in
        1)
            sed -i "s|USE_LOCAL_STT=.*|USE_LOCAL_STT=true|" "$SCRIPT_DIR/config.sh"
            sed -i "s|USE_LOCAL_TTS=.*|USE_LOCAL_TTS=true|" "$SCRIPT_DIR/config.sh"
            ;;
        2)
            sed -i "s|USE_LOCAL_STT=.*|USE_LOCAL_STT=false|" "$SCRIPT_DIR/config.sh"
            sed -i "s|USE_LOCAL_TTS=.*|USE_LOCAL_TTS=false|" "$SCRIPT_DIR/config.sh"
            echo
            read -p "Enter OpenAI API key: " api_key
            if [[ -n "$api_key" ]]; then
                echo "export OPENAI_API_KEY='$api_key'" >> ~/.bashrc
            fi
            ;;
        "")
            # Empty input - keep current settings
            echo "Keeping current audio settings"
            ;;
        *)
            echo "Invalid selection, keeping current settings"
            ;;
    esac
    
    echo
    echo "4. Testing Setup"
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
    
    # Test audio (basic)
    echo "Testing audio capabilities..."
    if command -v termux-tts-speak >/dev/null; then
        echo "✅ TTS available"
    else
        echo "❌ TTS not available - install termux-api"
        return 1
    fi
    
    if command -v termux-microphone-record >/dev/null; then
        echo "✅ Microphone recording available"
    else
        echo "❌ Microphone not available - install termux-api"
        return 1
    fi
    
    return 0
}

# Edit configuration
edit_config() {
    # Create config if it doesn't exist
    if [[ ! -f "$SCRIPT_DIR/config.sh" ]]; then
        echo "Creating new config file..."
        create_default_config > "$SCRIPT_DIR/config.sh"
        chmod +x "$SCRIPT_DIR/config.sh"
    fi
    
    if command -v nano >/dev/null; then
        nano "$SCRIPT_DIR/config.sh"
    elif command -v vim >/dev/null; then
        vim "$SCRIPT_DIR/config.sh"
    else
        echo "No editor available. Install nano or vim:"
        echo "pkg install nano"
    fi
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
        config)
            edit_config
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