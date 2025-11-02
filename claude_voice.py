#!/usr/bin/env python3
"""
Voice-enabled Claude TUI - Integrated Python Application

Provides voice input to Claude Code TUI via Ctrl+Space trigger.
Includes built-in TTS MCP server for Claude to speak responses.

Usage:
    python claude_voice.py [config_file]

Press Ctrl+Space to activate voice input.
Press Ctrl+C to exit.
"""

import sys
import os
import subprocess
import select
import tty
import termios
import signal
import json
import tempfile
import time
import pty
import socket
from pathlib import Path
from configparser import ConfigParser
from typing import Optional

try:
    from openai import OpenAI
except ImportError:
    print("ERROR: openai package not installed. Run: pip install openai")
    sys.exit(1)

# MCP server is now a separate script (tts_mcp_server.py)


class Config:
    """Load and validate configuration from INI file"""

    def __init__(self, config_path: str = "voice_config.ini"):
        self.config = ConfigParser()

        if not os.path.exists(config_path):
            print(f"ERROR: Config file not found: {config_path}")
            print(f"Copy voice_config.ini.example to {config_path} and edit with your settings")
            sys.exit(1)

        self.config.read(config_path)
        self._validate()

    def _validate(self):
        """Validate required config sections and keys"""
        required = {
            'ssh': ['host', 'user', 'key_path'],  # dev_path is optional (can use CLI arg)
            'claude': ['path'],
            'openai': ['api_key'],
            'tts': ['pitch', 'rate']
        }

        for section, keys in required.items():
            if section not in self.config:
                print(f"ERROR: Missing [{section}] section in config")
                sys.exit(1)
            for key in keys:
                if key not in self.config[section]:
                    print(f"ERROR: Missing {key} in [{section}] section")
                    sys.exit(1)

    def get(self, section: str, key: str, fallback=None):
        """Get config value with optional fallback"""
        return self.config.get(section, key, fallback=fallback)

    def getint(self, section: str, key: str, fallback=None):
        """Get config integer value"""
        return self.config.getint(section, key, fallback=fallback)

    def getfloat(self, section: str, key: str, fallback=None):
        """Get config float value"""
        return self.config.getfloat(section, key, fallback=fallback)


class VoiceInputHandler:
    """Handle voice input via Ctrl+Space trigger"""

    def __init__(self, config: Config):
        self.config = config
        self.openai_client = OpenAI(api_key=config.get('openai', 'api_key'))

    def cleanup_existing_recording(self):
        """Stop any existing recording sessions"""
        try:
            subprocess.run(['termux-microphone-record', '-q'],
                         capture_output=True, timeout=1)
        except:
            pass

    def record_audio(self) -> Optional[Path]:
        """Record audio using termux-microphone-record (manual stop mode)"""
        # Ensure no recording is already in progress
        self.cleanup_existing_recording()

        temp_file = Path(tempfile.mktemp(suffix='.m4a'))

        # Remove existing file if it exists
        if temp_file.exists():
            temp_file.unlink()

        try:
            # Manual stop mode - start recording in background
            sys.stderr.write("\r\n🎤 Recording... (press Enter to stop)\r\n")
            sys.stderr.flush()

            # Start recording with no time limit (-l 0)
            subprocess.Popen(
                ['termux-microphone-record', '-f', str(temp_file), '-l', '0', '-e', 'aac'],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )

            # Return temp file path - caller will wait for stop signal
            return temp_file

        except Exception as e:
            sys.stderr.write(f"\r\n❌ Recording error: {e}\r\n")
            sys.stderr.flush()
            self.cleanup_existing_recording()
            return None

    def transcribe_audio(self, audio_file: Path) -> Optional[str]:
        """Transcribe audio using OpenAI Whisper API"""
        sys.stderr.write("🔄 Transcribing...\r\n")
        sys.stderr.flush()

        try:
            with open(audio_file, 'rb') as f:
                response = self.openai_client.audio.transcriptions.create(
                    model="whisper-1",
                    file=f,
                    language="en"
                )

            text = response.text.strip()

            if text:
                sys.stderr.write(f"✅ Transcribed: {text}\r\n")
                sys.stderr.flush()
                return text
            else:
                sys.stderr.write("❌ Empty transcription\r\n")
                sys.stderr.flush()
                return None

        except Exception as e:
            sys.stderr.write(f"❌ Transcription error: {e}\r\n")
            sys.stderr.flush()
            return None
        finally:
            # Clean up temp file
            if audio_file.exists():
                audio_file.unlink()

    def get_voice_input(self, stop_callback) -> Optional[str]:
        """Record and transcribe voice input (manual stop mode)

        Args:
            stop_callback: Function to call to wait for stop signal
        """
        audio_file = self.record_audio()
        if not audio_file:
            return None

        # Wait for stop signal
        stop_callback()  # Wait for user to press Ctrl+Space again

        # Stop recording
        self.cleanup_existing_recording()
        sys.stderr.write("✅ Recording stopped\r\n")
        sys.stderr.flush()

        # Wait a bit for file to be written
        time.sleep(0.5)

        # Check if file exists and has content
        if not audio_file.exists() or audio_file.stat().st_size < 1000:
            sys.stderr.write("❌ Recording failed or too short\r\n")
            sys.stderr.flush()
            if audio_file.exists():
                audio_file.unlink()
            return None

        return self.transcribe_audio(audio_file)


class ClaudeVoiceTUI:
    """Main application: SSH to Claude with voice input support"""

    def __init__(self, config_path: str = "voice_config.ini", working_dir: Optional[str] = None):
        self.config = Config(config_path)
        self.voice_handler = VoiceInputHandler(self.config)
        self.working_dir = working_dir  # Override for dev_path from CLI

        # Setup signal handlers
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)

    def _signal_handler(self, signum, frame):
        """Handle shutdown signals"""
        print("\n\nShutting down...", file=sys.stderr)
        self.cleanup()
        sys.exit(0)

    def get_mcp_config(self) -> dict:
        """Generate MCP configuration for Claude"""
        termux_ip = self.get_termux_ip_from_ssh()
        termux_user = os.getenv('USER')  # Current Termux username
        script_dir = os.path.dirname(os.path.abspath(__file__))

        # MCP config for Claude to SSH to Termux and run the MCP server
        # Termux sshd runs on port 8022 by default
        return {
            "mcpServers": {
                "termux-tts": {
                    "command": "ssh",
                    "args": [
                        "-p", "8022",
                        "-o", "StrictHostKeyChecking=no",
                        f"{termux_user}@{termux_ip}",
                        f"cd {script_dir} && python3 tts_mcp_server.py"
                    ],
                    "env": {}
                }
            }
        }

    def get_termux_ip_from_ssh(self) -> str:
        """Get Termux's IP as seen from the dev machine"""
        # Get local IP that would be used to connect to dev machine
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect((self.config.get('ssh', 'host'), 1))
        ip = s.getsockname()[0]
        s.close()
        return ip

    def build_ssh_command(self):
        """Build SSH command for Claude"""
        ssh_key = os.path.expanduser(self.config.get('ssh', 'key_path'))
        ssh_host = self.config.get('ssh', 'host')
        ssh_user = self.config.get('ssh', 'user')
        # Use CLI argument if provided, otherwise fall back to config
        dev_path = self.working_dir if self.working_dir else self.config.get('ssh', 'dev_path', fallback='~')
        claude_path = os.path.expanduser(self.config.get('claude', 'path'))

        # Build MCP config
        mcp_config = self.get_mcp_config()
        mcp_json = json.dumps(mcp_config)

        # SSH command to run Claude with MCP config
        system_prompt = "IMPORTANT: After providing your response to the user, use the mcp__termux-tts__speak tool to speak a concise vocal summary (1-2 sentences) of your reply. This helps the user understand your response through voice feedback."
        return [
            'ssh',
            '-i', ssh_key,
            '-t',  # Force TTY allocation
            f'{ssh_user}@{ssh_host}',
            f'cd {dev_path} && {claude_path} --mcp-config \'{mcp_json}\' --append-system-prompt \'{system_prompt}\''
        ]

    def stdin_read(self, fd):
        """Custom stdin read function to intercept Ctrl+Space"""
        # Read from stdin
        data = os.read(fd, 1024)

        # Check for Ctrl+Space (0x00)
        if b'\x00' in data:
            # Handle voice input synchronously and get the result
            voice_text = self._handle_voice_input_sync(fd)

            # Remove Ctrl+Space from data
            data = data.replace(b'\x00', b'')

            # If we got voice text, return it
            if voice_text:
                return voice_text

        return data

    def _handle_voice_input_sync(self, stdin_fd):
        """Handle voice input synchronously and return the transcribed text"""
        # Save current terminal settings
        old_tty = termios.tcgetattr(stdin_fd)

        try:
            # Set to cooked mode for better output during voice interaction
            tty.setcbreak(stdin_fd)

            # Define callback for waiting on stop signal in manual mode
            def wait_for_stop():
                # Use \r\n for proper output in raw terminal
                sys.stderr.write("\r\nPress Enter to stop recording...\r\n")
                sys.stderr.flush()

                # Wait for Enter key
                while True:
                    char = os.read(stdin_fd, 1)
                    if char == b'\r':  # Enter key
                        break

            # Get voice input
            text = self.voice_handler.get_voice_input(stop_callback=wait_for_stop)

            if text:
                # Return the text bytes - user can review and press Enter to send
                return text.encode('utf-8')
            else:
                return None

        except Exception as e:
            sys.stderr.write(f"\r\n❌ Voice input error: {e}\r\n")
            sys.stderr.flush()
            return None
        finally:
            # Restore original terminal mode
            termios.tcsetattr(stdin_fd, termios.TCSADRAIN, old_tty)

    def cleanup(self):
        """Clean up resources"""
        # Cleanup any leftover recordings
        self.voice_handler.cleanup_existing_recording()

    def run(self):
        """Main application loop"""
        try:
            # Cleanup any existing recordings first
            self.voice_handler.cleanup_existing_recording()

            # Build SSH command
            ssh_cmd = self.build_ssh_command()

            ssh_host = self.config.get('ssh', 'host')
            dev_path = self.working_dir if self.working_dir else self.config.get('ssh', 'dev_path', fallback='~')
            print(f"Connecting to Claude on {ssh_host}...", file=sys.stderr)
            print(f"Working directory: {dev_path}", file=sys.stderr)
            print("Press Ctrl+Space to record, Enter to stop, Enter again to send, Ctrl+C to exit\n", file=sys.stderr)

            # Use pty.spawn() for proper terminal handling
            # This automatically handles all PTY setup and cleanup
            pty.spawn(ssh_cmd, stdin_read=self.stdin_read)

        except KeyboardInterrupt:
            print("\n\nInterrupted by user", file=sys.stderr)
        except Exception as e:
            print(f"\nError: {e}", file=sys.stderr)
            import traceback
            traceback.print_exc()
        finally:
            self.cleanup()


def main():
    """Entry point"""
    import argparse

    parser = argparse.ArgumentParser(
        description='Voice-enabled Claude TUI',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
Usage:
  %(prog)s [path]                    # Start in specified directory
  %(prog)s --config FILE [path]      # Use custom config file

Examples:
  %(prog)s ~/projects/myapp          # Start in ~/projects/myapp
  %(prog)s                           # Use directory from config
  %(prog)s --config my.ini ~/code    # Custom config + directory
        '''
    )
    parser.add_argument(
        'path',
        nargs='?',
        help='Working directory on dev machine (overrides config)'
    )
    parser.add_argument(
        '--config',
        default='voice_config.ini',
        help='Path to config file (default: voice_config.ini)'
    )

    args = parser.parse_args()

    app = ClaudeVoiceTUI(args.config, working_dir=args.path)
    app.run()


if __name__ == '__main__':
    main()
