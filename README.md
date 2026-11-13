# RDGen, a RustDesk client generator to use with your self-hosted RustDesk server

The client generator is currently hosted [here](https://rdgen.crayoneater.org).
If you would like to host the generator yourself, see [here](setup.md)

## rustdesk api server integration

The rdgen client generator is integrated into my fork of the [rustdesk-api](https://github.com/bryangerlach/rustdesk-api). This is currently a work in progress, and might have bugs.

## rdgen local build alternative

If you would prefer to build rustdesk on your own computer, check out the [DVForge](https://github.com/VenimK/DVForge) project.

## Features

- Embed server and key into client
- Custom app name
- Custom icon/logo
- Custom theme colors (accent, light/dark surfaces, ID/“me” color)
- Set default settings for the client
- Support for rustdesk advanced settings (https://rustdesk.com/docs/en/self-host/client-configuration/advanced-settings/)

## Generate RustDesk clients from command line instead of using a web browser

Save your configuration from the rdgen web interface, or generate your own, then use that json file with [@AlekseyLapunov's rdgen-cli](https://github.com/AlekseyLapunov/rdgen-cli) to build from the command line on Windows, Linux, or MacOS like this: `python rdgen-cli -f my_config.json --set-version 1.4.5 --set-platform windows -s https://rdgen.crayoneater.org`

## Notes

- Icons should be square (256x256 recommended)
- Avoid special characters or non-English characters in app name and file name
- Build time is currently 30 - 45 minutes
- Permissions and security settings are written to `override-settings`, so they also apply to machines that already have a saved RustDesk configuration and cannot be changed by the client. The old Default/Override selector for permissions was removed.
- A permanent password baked into a client is always accepted, even if the machine already has a local permanent password. Setting one also selects permanent-password verification.

