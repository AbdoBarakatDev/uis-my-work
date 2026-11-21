# UIS My Work

A Chrome and Edge extension for the UIS team. It puts your portal.uiscom.com work in one focused dashboard:

- **My Day:** what to focus on, approvals waiting on you, and upcoming deadlines.
- **Board and list:** tasks from backlog to done.
- **Approvals:** review, test and accept tasks, with the evidence the portal asks for.
- **Requests:** new tasks, edits and deletions waiting for an approver.
- **Team and chat:** each teammate's progress, and direct messages.

New versions install themselves.

**Setup page:** https://abdobarakatdev.github.io/uis-my-work/ (English and Arabic)

It works on your own signed-in portal tab and stores no passwords. Every action runs as you.

---

## Setup on Windows

1. **Download the installer:** [UIS-MyWork-LiveUpdates.ps1](https://github.com/AbdoBarakatDev/uis-my-work/releases/latest/download/UIS-MyWork-LiveUpdates.ps1)
   If Chrome asks whether to keep the file, choose **Keep**. Chrome asks this for every script file.
2. **Run it once.** Right-click the file and choose **Run with PowerShell**. On Windows 11, click **Show more options** first.
   - It takes about a minute.
   - It installs for your Windows user only and needs no admin rights.
   - At the end it copies the extension's folder path for you.
3. **Load it in Chrome or Edge.**
   1. Open `chrome://extensions` (Edge: `edge://extensions`).
   2. Turn on **Developer mode**.
   3. If you have an older copy, remove "UIS Portal – My Work Tracker".
   4. Click **Load unpacked**, paste the folder path (<kbd>Ctrl</kbd>+<kbd>V</kbd>) and click **Select Folder**.

   The folder is `%LOCALAPPDATA%\UIS\MyWork\extension`.
4. **Start.** Sign in to portal.uiscom.com, click the UIS My Work icon and choose **Open dashboard**. You can pin the icon from the puzzle-piece menu.

## Setup on Mac

1. **Download the installer:** [UIS-MyWork-LiveUpdates.sh](https://github.com/AbdoBarakatDev/uis-my-work/releases/latest/download/UIS-MyWork-LiveUpdates.sh)
2. **Run it once.**
   1. Open **Terminal**: press <kbd>⌘</kbd>+<kbd>Space</kbd>, type Terminal and press <kbd>Return</kbd>.
   2. Type `bash` and a space.
   3. Drag `UIS-MyWork-LiveUpdates.sh` from Downloads into the Terminal window and press <kbd>Return</kbd>.

   It takes about a minute, installs for your Mac user only and needs no admin password. At the end it copies the extension's folder path for you.
3. **Load it in Chrome or Edge.**
   1. Open `chrome://extensions` and turn on **Developer mode**.
   2. If you have an older copy, remove it.
   3. Click **Load unpacked** and press <kbd>⌘</kbd>+<kbd>⇧</kbd>+<kbd>G</kbd>.
   4. Paste the folder path (<kbd>⌘</kbd>+<kbd>V</kbd>), press <kbd>Return</kbd> and click **Select**.

   The folder is `~/Library/Application Support/UIS/MyWork/extension`.
4. **Start.** Sign in to portal.uiscom.com, click the UIS My Work icon and choose **Open dashboard**.

## Without live updates (any system)

1. Download [uis-my-work.zip](https://github.com/AbdoBarakatDev/uis-my-work/releases/latest/download/uis-my-work.zip).
2. Unzip it into a folder you keep, such as `Documents/UIS My Work`. Don't use your Downloads folder.
3. In `chrome://extensions`, turn on **Developer mode**, click **Load unpacked** and choose that folder.
4. To update, unzip each new zip over the same folder and press ↻ on the extension's card.

## What the installer does

| | Windows | Mac |
|---|---|---|
| Extension | `%LOCALAPPDATA%\UIS\MyWork\extension` | `~/Library/Application Support/UIS/MyWork/extension` |
| Updater | `%LOCALAPPDATA%\UIS\MyWork\updater` | `~/Library/Application Support/UIS/MyWork/updater` |
| Registered for | Chrome and Edge, this Windows user (HKCU) | Chrome, Edge and Brave, this Mac user |

- Only the UIS My Work extension can start the updater. The updater's manifest allows that extension ID and no other.
- The updater downloads only from the UIS update server, `https://uis-mobile-portal.web.app`.
- It checks each download's SHA-256 checksum before using it, and never runs what it downloads.
- You can read the whole source in [installers/](installers/):
  - [Windows](installers/windows/UIS-MyWork-LiveUpdates.ps1)
  - [Mac](installers/mac/UIS-MyWork-LiveUpdates.sh)

**Turn live updates off:** run the remover the same way you ran the installer. It removes the updater and keeps the extension folder.

- Windows: [UIS-MyWork-RemoveLiveUpdates.ps1](https://github.com/AbdoBarakatDev/uis-my-work/releases/latest/download/UIS-MyWork-RemoveLiveUpdates.ps1)
- Mac: [UIS-MyWork-RemoveLiveUpdates.sh](https://github.com/AbdoBarakatDev/uis-my-work/releases/latest/download/UIS-MyWork-RemoveLiveUpdates.sh)

**Remove everything:**
1. Run the remover.
2. Remove the extension card in `chrome://extensions`.
3. Delete the `UIS\MyWork` folder.

## In this repository

- `index.html`: the setup page, published with GitHub Pages.
- `installers/`: the live-updates installers and removers, readable as text.
- [Releases](https://github.com/AbdoBarakatDev/uis-my-work/releases): each version's `uis-my-work.zip` and its installers.

UIS My Work is an internal tool for the UIS team. If something doesn't work, run the installer again, which is safe to repeat. If that doesn't fix it, ask your UIS My Work admin.
