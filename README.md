# PhoneThing

PhoneThing is a two-part prototype:

- `PhoneThing.PC`: a Windows desktop receiver app with a local HTTP endpoint and a live command log
- `PhoneThingRemote`: a native SwiftUI iPhone app that sends media-control commands over your local network

For this first version, the iPhone app only sends commands and the PC app only displays what it received. Nothing on the PC actually controls media yet.

## What works right now

- Previous track command
- Play / pause command
- Next track command
- Volume command with a percentage value
- Simple local-network communication between phone and PC
- A Windows UI that clearly shows the last received command and keeps a command history

## PC app: run and build

### Option 1: run from source

1. Open `PhoneThing.sln` in Visual Studio 2022 or newer.
2. Run the `PhoneThing.PC` project.
3. The app will show the exact `http://<your-ip>:5050/api/commands` addresses that the phone can use.

### Option 2: produce an easy-to-run `.exe`

1. Open PowerShell in the repo root.
2. Run:

```powershell
.\scripts\publish-pc.ps1
```

3. After publishing, use:

```text
dist\pc\PhoneThing.PC.exe
```

That publish step creates a self-contained Windows executable, so it can run even on a PC without the .NET runtime installed.

## iPhone app: open and sideload

You will need a Mac with Xcode to install the iPhone app on your device.

1. Copy this repo to your Mac.
2. Open `PhoneThingRemote/PhoneThingRemote.xcodeproj` in Xcode.
3. Select the `PhoneThingRemote` target.
4. In `Signing & Capabilities`, choose your Apple ID team.
5. Plug in your iPhone or select it from Xcode's device list.
6. Build and run the app.
7. If iOS warns that the developer is untrusted, go to:

```text
Settings > General > VPN & Device Management
```

8. Trust your Apple ID's developer profile, then open the app again.

### First-time connection steps

1. Launch the Windows app first.
2. Make sure the phone and PC are on the same Wi-Fi network.
3. In the iPhone app, enter the PC's IP address exactly as shown in the Windows app.
4. Tap the media buttons or send the volume value.
5. The Windows app should immediately show the received command.

## Notes for the next phase

When you're ready, the next logical steps are:

1. Replace the PC log-only behavior with real media control handlers.
2. Add pairing and auto-discovery so you don't have to type the IP manually.
3. Add app-specific routes, including Spotify-specific volume if we decide to integrate that separately.
