#!/bin/bash
# Script to permanently hide Security, Network, and Printer settings tabs
# Works for both Desktop (Windows/macOS) and Mobile (Android/iOS)

DESKTOP_FILE="flutter/lib/desktop/pages/desktop_setting_page.dart"
MOBILE_FILE="flutter/lib/mobile/pages/settings_page.dart"

echo "=== HIDING GRANULAR SETTINGS ==="

# Use Python for reliable multi-line replacement
python3 << 'PYTHON_SCRIPT'
import re
import os

desktop_file = "flutter/lib/desktop/pages/desktop_setting_page.dart"
mobile_file = "flutter/lib/mobile/pages/settings_page.dart"

# Process Desktop file if it exists
if os.path.exists(desktop_file):
    print(f"Processing {desktop_file}...")
    with open(desktop_file, 'r') as f:
        content = f.read()

    # Replace General Settings block
    content = re.sub(
        r'(\s+)SettingsTabKey\.general,',
        r'\1// GENERAL SETTINGS PERMANENTLY HIDDEN\n\1// SettingsTabKey.general,',
        content,
        flags=re.MULTILINE | re.DOTALL
    )

    # Replace Security Settings block
    content = re.sub(
        r'(\s+)if \(!isWeb &&\s+!bind\.isOutgoingOnly\(\) &&\s+!bind\.isDisableSettings\(\) &&\s+bind\.mainGetBuildinOption\(key: kOptionHideSecuritySetting\) != \'Y\'\)\s+SettingsTabKey\.safety,',
        r'\1// SECURITY SETTINGS PERMANENTLY HIDDEN\n\1// if (!isWeb &&\n\1//     !bind.isOutgoingOnly() &&\n\1//     !bind.isDisableSettings() &&\n\1//     bind.mainGetBuildinOption(key: kOptionHideSecuritySetting) != \'Y\')\n\1//   SettingsTabKey.safety,',
        content,
        flags=re.MULTILINE | re.DOTALL
    )

    # Replace Network Settings block
    content = re.sub(
        r'(\s+)if \(!bind\.isDisableSettings\(\) &&\s+bind\.mainGetBuildinOption\(key: kOptionHideNetworkSetting\) != \'Y\'\)\s+SettingsTabKey\.network,',
        r'\1// NETWORK SETTINGS PERMANENTLY HIDDEN\n\1// if (!bind.isDisableSettings() &&\n\1//     bind.mainGetBuildinOption(key: kOptionHideNetworkSetting) != \'Y\')\n\1//   SettingsTabKey.network,',
        content,
        flags=re.MULTILINE | re.DOTALL
    )

    # Replace Display Settings block
    content = re.sub(
        r'(\s+)if \(!bind\.isIncomingOnly\(\)\)\s+SettingsTabKey\.display,',
        r'\1// DISPLAY SETTINGS PERMANENTLY HIDDEN\n\1// if (!bind.isIncomingOnly())\n\1//   SettingsTabKey.display,',
        content,
        flags=re.MULTILINE | re.DOTALL
    )

    # Replace Account Settings block
    content = re.sub(
        r'(\s+)if \(!bind\.isDisableAccount\(\)\)\s+SettingsTabKey\.account,',
        r'\1// ACCOUNT SETTINGS PERMANENTLY HIDDEN\n\1// if (!bind.isDisableAccount())\n\1//   SettingsTabKey.account,',
        content,
        flags=re.MULTILINE | re.DOTALL
    )

    # Replace Plugin Settings block
    content = re.sub(
        r'(\s+)if \(!isWeb &&\s+!bind\.isIncomingOnly\(\) &&\s+bind\.pluginFeatureIsEnabled\(\)\)\s+SettingsTabKey\.plugin,',
        r'\1// PLUGIN SETTINGS PERMANENTLY HIDDEN\n\1// if (!isWeb && !bind.isIncomingOnly() && bind.pluginFeatureIsEnabled())\n\1//   SettingsTabKey.plugin,',
        content,
        flags=re.MULTILINE | re.DOTALL
    )

    # Replace Printer Settings block
    content = re.sub(
        r'(\s+)if \(isWindows &&\s+bind\.mainGetBuildinOption\(key: kOptionHideRemotePrinterSetting\) != \'Y\'\)\s+SettingsTabKey\.printer,',
        r'\1// PRINTER SETTINGS PERMANENTLY HIDDEN\n\1// if (isWindows &&\n\1//     bind.mainGetBuildinOption(key: kOptionHideRemotePrinterSetting) != \'Y\')\n\1//   SettingsTabKey.printer,',
        content,
        flags=re.MULTILINE | re.DOTALL
    )

    with open(desktop_file, 'w') as f:
        f.write(content)
    print(f"✅ Desktop settings tabs hidden")
else:
    print(f"⚠️  {desktop_file} not found, skipping desktop modifications")

# Process Mobile file if it exists
if os.path.exists(mobile_file):
    print(f"\nProcessing {mobile_file}...")
    with open(mobile_file, 'r') as f:
        mobile_content = f.read()
    
    # Mobile uses SettingsList sections, not tabs
    # Hide sections based on the decoded config flags
    # The structure is: if (!condition) SettingsSection(...)
    
    # For mobile, we comment out entire SettingsSection blocks
    # General settings section
    mobile_content = re.sub(
        r'(\s+)SettingsSection\([^)]*title:[^)]*[\'"]General[\'"][^}]*\}\)',
        r'\1// GENERAL SETTINGS PERMANENTLY HIDDEN\n\1// SettingsSection(title: "General", ...)',
        mobile_content,
        flags=re.DOTALL
    )
    
    # Security settings section
    mobile_content = re.sub(
        r'(\s+)if \(!bind\.isOutgoingOnly\(\)\)[^{]*\{[^}]*[\'"]Security[\'"][^}]*\}',
        r'\1// SECURITY SETTINGS PERMANENTLY HIDDEN\n\1// if (!bind.isOutgoingOnly()) { ... Security section ... }',
        mobile_content,
        flags=re.DOTALL
    )
    
    with open(mobile_file, 'w') as f:
        f.write(mobile_content)
    print(f"✅ Mobile settings sections hidden")
else:
    print(f"⚠️  {mobile_file} not found, skipping mobile modifications")

print("\n✅ Granular settings hiding complete!")
PYTHON_SCRIPT

echo "=== GRANULAR SETTINGS HIDING COMPLETE ==="
