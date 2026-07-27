# RustDesk Creator

A web-based tool for creating custom RustDesk clients with your own branding and configuration.

## Features

- Custom branding (app name, icons, logos)
- Pre-configured connection settings
- Security and permission defaults
- Multi-platform support (Windows, macOS, Linux, Android)
- Automatic build and delivery

## Configuration Options

### Basic Settings
- **App Name**: Your custom application name (e.g., "MyRemoteDesktop")
- **Platform**: Choose your target platform
  - Windows (64-bit)
  - macOS (Intel/ARM)
  - Linux (currently unavailable)
  - Android
- **Version**: Select RustDesk version
  - Stable releases (1.3.3 - 1.4.3)
  - Master/Nightly (latest development version, may be unstable)

### Branding
- **Custom Icon**: Upload a square PNG image for your app icon
- **Custom Logo**: Upload a PNG image for the in-app logo
- **Custom Colors**: Set your brand colors for the UI

### Connection Settings
- **Relay Server**: Your custom relay server address
- **API Server**: Your custom API server address
- **Key**: Your custom public key for connection encryption
- **Connection Type**: Choose between incoming/outgoing connections
- **Default Connection Mode**: Set the default connection mode (view-only, control, file-transfer)

### Security
- **Run as Administrator**: Always run with elevated privileges (Windows)
- **Password Protection**: Set default connection password
- **Approval Mode**: Choose between password, click, or both for connection approval
- **LAN Discovery**: Enable/disable local network device discovery

### Permissions
Two modes available:
1. **Default Settings**: Users can change these later
   - Keyboard/Mouse control
   - File transfer
   - Audio
   - Clipboard
   - Session recording
2. **Override Settings**: Settings are locked and cannot be changed by users

## Build Results

After configuration, you'll receive:

### Windows
- Installer: `YourAppName-{version}-windows.exe`
- Portable: `YourAppName-{version}-windows-portable.exe`

### macOS
- DMG installer: `YourAppName-{version}-macos.dmg`
- Available for both Intel and Apple Silicon

### Android
- APK file: `YourAppName-{version}-android.apk`
- Split APKs for different architectures (arm64-v8a, armeabi-v7a, x86_64)

### Linux
- PKG file: `YourAppName-{version}-linux.pkg`
- DEB file: `YourAppName-{version}-linux.deb`
- RPM file: `YourAppName-{version}-linux.rpm`
- SUSE RPM file: `YourAppName-{version}-linux-suse.rpm`

## Important Notes

1. **Build Time**: Depending on the platform, builds can take 15-30 minutes
2. **Icons**: 
   - Must be square PNG images
   - Recommended size: 256x256 pixels
   - Will be automatically converted to required formats
3. **Version Selection**:
   - Stable versions recommended for production use
   - Master/nightly builds may include latest features but can be unstable
4. **Server Configuration**:
   - Ensure your relay/API servers are properly configured and accessible
   - Test server connectivity before deploying to users

## Troubleshooting

- If the build fails, check:
  1. Icon/logo format and dimensions
  2. Server addresses format
  3. Public key format
  4. Selected version compatibility
  
- For connection issues:
  1. Verify server configurations
  2. Check firewall settings
  3. Ensure public key matches your server

## Support

For issues or questions:
- Open an issue on GitHub
- Join our community discussions
- Check the documentation for updates

## License

This project is licensed under the AGPL-3.0 License.
