#!/usr/bin/env python3
"""
TTS MCP Server for Termux

Provides text-to-speech capability via MCP protocol using termux-tts-speak.
This server uses stdio transport and is launched via SSH by Claude Code.

Usage:
    python tts_mcp_server.py
"""

import subprocess
from configparser import ConfigParser
from pathlib import Path
from mcp.server.fastmcp import FastMCP

# Load TTS configuration
config_path = Path(__file__).parent / "voice_config.ini"
config = ConfigParser()
config.read(config_path)

TTS_PITCH = config.getfloat('tts', 'pitch', fallback=1.0)
TTS_RATE = config.getfloat('tts', 'rate', fallback=2.0)

# Create MCP server
mcp = FastMCP("termux-tts")


@mcp.tool()
def speak(text: str) -> str:
    """
    Speak text aloud using Android text-to-speech.

    Guidelines:
    - Keep spoken text brief and conversational
    - Describe any code at a high level
    - Example: "I've added the login validation function to auth.py"

    Args:
        text: The text to speak aloud (keep it concise for voice)

    Returns:
        Status message indicating success or error
    """
    cmd = [
        'termux-tts-speak',
        '-p', str(TTS_PITCH),
        '-r', str(TTS_RATE),
        text
    ]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if result.returncode == 0:
            return f"Successfully spoke: {text[:50]}{'...' if len(text) > 50 else ''}"
        else:
            return f"TTS error: {result.stderr}"
    except subprocess.TimeoutExpired:
        return "TTS error: timeout (speech took too long)"
    except Exception as e:
        return f"TTS error: {str(e)}"


if __name__ == "__main__":
    # Run the MCP server with stdio transport
    mcp.run()
