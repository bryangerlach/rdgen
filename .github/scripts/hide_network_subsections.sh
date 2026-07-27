#!/bin/bash
# Script to hide sub-sections within Network Settings tab
# These are sections like Server Settings, Proxy Settings, WebSocket Settings

echo "=== HIDING NETWORK SUB-SECTIONS ==="

# Decode custom config to see what needs to be hidden
DECODED_CONFIG="$1"

# Function to hide specific sections in network settings
hide_network_sections() {
    echo "Modifying Network settings UI to hide selected sub-sections..."
    
    # Use Python for reliable multi-line search and replace
    python3 << 'PYTHON_SCRIPT'
import re
import sys
import json

# Read the decoded config from environment or stdin
import os
decoded_config = os.environ.get('DECODED_CONFIG', '{}')

try:
    config = json.loads(decoded_config)
except:
    print("Warning: Could not parse config JSON")
    config = {}

# Determine which sections to hide based on config
hide_server = config.get('hide-server-settings') == 'Y'
hide_proxy = config.get('hide-proxy-settings') == 'Y'
hide_websocket = config.get('hide-websocket-settings') == 'Y'

print(f"Hide Server Settings: {hide_server}")
print(f"Hide Proxy Settings: {hide_proxy}")
print(f"Hide WebSocket Settings: {hide_websocket}")

# Find and modify the network settings files
# The network settings are typically in flutter/lib/desktop/pages/desktop_setting_page.dart
# But the actual UI sections are rendered dynamically

# We need to find where _buildNetwork() or similar methods render these sections
# For now, let's create a more aggressive approach: modify the settings based on option checks

file_paths = [
    "flutter/lib/desktop/pages/desktop_setting_page.dart",
    "flutter/lib/common/widgets/setting_widgets.dart"
]

for file_path in file_paths:
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        original_content = content
        modified = False
        
        # Look for ID Server / Relay Server settings
        if hide_server:
            # Find and comment out relay server input fields
            patterns = [
                (r'([\s]*)(_buildIDServer\(\))', r'\1// SERVER SETTINGS HIDDEN\n\1// \2'),
                (r'([\s]*)(_buildRelayServer\(\))', r'\1// SERVER SETTINGS HIDDEN\n\1// \2'),
                (r'([\s]*)(SettingWidgets\.buildIDServer)', r'\1// SERVER SETTINGS HIDDEN\n\1// \2'),
            ]
            for pattern, replacement in patterns:
                if re.search(pattern, content):
                    content = re.sub(pattern, replacement, content)
                    modified = True
                    print(f"  ✓ Hid server settings in {file_path}")
        
        # Look for Proxy settings
        if hide_proxy:
            patterns = [
                (r'([\s]*)(_buildProxy\(\))', r'\1// PROXY SETTINGS HIDDEN\n\1// \2'),
                (r'([\s]*)(SettingWidgets\.buildProxy)', r'\1// PROXY SETTINGS HIDDEN\n\1// \2'),
            ]
            for pattern, replacement in patterns:
                if re.search(pattern, content):
                    content = re.sub(pattern, replacement, content)
                    modified = True
                    print(f"  ✓ Hid proxy settings in {file_path}")
        
        # Look for WebSocket settings  
        if hide_websocket:
            patterns = [
                (r'([\s]*)(_buildWebSocket\(\))', r'\1// WEBSOCKET SETTINGS HIDDEN\n\1// \2'),
                (r'([\s]*)(SettingWidgets\.buildWebSocket)', r'\1// WEBSOCKET SETTINGS HIDDEN\n\1// \2'),
            ]
            for pattern, replacement in patterns:
                if re.search(pattern, content):
                    content = re.sub(pattern, replacement, content)
                    modified = True
                    print(f"  ✓ Hid websocket settings in {file_path}")
        
        if modified and content != original_content:
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(content)
            print(f"✅ Modified {file_path}")
    
    except FileNotFoundError:
        pass
    except Exception as e:
        print(f"Warning: Could not modify {file_path}: {e}")

print("✅ Network sub-sections hiding completed")
PYTHON_SCRIPT
}

# Export the decoded config for Python to read
export DECODED_CONFIG="$DECODED_CONFIG"

# Run the hiding function
hide_network_sections

echo "=== NETWORK SUB-SECTIONS HIDING COMPLETE ==="
