# 🐧 Applications Manager for Linux

A powerful, unified, and interactive terminal-based installer for Linux applications. 

**Applications Manager** simplifies the way you install, update, and manage software on your Linux system by bringing multiple package sources (GitHub, Flatpak, APT, and Direct URLs) into one beautiful and easy-to-use interface.

---

## ✨ Features

- 🚀 **Unified Installation:** Install apps from GitHub Releases, Flathub, system repositories (APT), or direct download links.
- 📦 **66+ Pre-configured Apps:** Comes with a ready-to-use list of popular apps (Blender, GIMP, Krita, Godot, VS Code, Geany, etc.).
- 🧠 **Smart Archive Flattening:** Automatically detects and flattens deeply nested folders inside `.zip` or `.tar.gz` archives (e.g., `-__w/flameshot/flameshot/AppImage`).
- 🔄 **Smart Updates:** Checks for updates by comparing installed versions with the latest remote versions using `sort -V`.
- 🛡️ **APT Support:** Seamlessly install native system packages without leaving the terminal interface.
- 🎨 **Beautiful UI:** Colorful terminal menus, progress bars, and clear feedback.
- 🔒 **Runs as Root:** Integrates with `pkexec` and `sudo` to ensure apps have the necessary permissions to run.
- 🌐 **API Token Optional:** Works anonymously (60 req/hour), but supports a GitHub Personal Access Token to bypass rate limits (5000 req/hour).
- 🩺 **Dependency Checker:** Automatically verifies and helps you install required tools (`jq`, `curl`, `wget`).

---

## 📸 Screenshots
https://github.com/Warren-15/Linux_app_manager/blob/main/Screens/1%20-%20main.jpg?raw=true


## 🚀 Installation

### Prerequisites
- A Debian-based Linux distribution (Ubuntu, Mint, Pop!_OS, Debian, etc.)
- Basic tools: `bash`, `curl`, `jq`, `wget`, `tar`, `unzip`

### 1. Clone the Repository
```bash
git clone https://github.com/YOUR_USERNAME/applications-manager.git
cd applications-manager
```

### 2. Make it Executable
```bash
chmod +x install_app.sh
```

### 3. Run the Manager
*(The script requires `sudo` to install apps to `/Applications` and system directories)*
```bash
sudo ./install_app.sh
```

---

## 📖 Usage

Upon running the script, you will be greeted with the main menu:

```text
  0. Check for Updates / Download
  1. Install (Queue)
  2. Create / Edit Category
  3. Create Shortcut
  4. Edit Shortcuts
  5. Remove
  6. Settings
  7. Exit
```

### 📥 How to Install Apps
1. Go to **`0. Check for Updates / Download`**.
2. Select **`2. Download new apps`**.
3. Filter by category (e.g., *Graphics*, *Programming*).
4. Select the apps you want (e.g., `1 3 5`).
5. Choose **`1. Download & Install`**.

### 🔄 How to Update Apps
1. Go to **`0. Check for Updates`**.
2. Select **`1. Check for updates`**.
3. The script will scan your installed apps and compare them with the latest versions.
4. If updates are available, select them and install.

---

## 🛠️ Configuration

### Adding Custom Apps
You can add your own applications by editing `data/program list.txt`. The file is TAB-separated:

```text
AppName	Category	Description	Format	Source	Repo/URL
```

| Field | Options | Example |
|-------|---------|---------|
| **Format** | `AppImage`, `zip`, `tar.gz`, `tar.xz`, `apt` | `AppImage` |
| **Source** | `github`, `flatpak`, `apt`, `folder`, `direct` | `github` |
| **Repo/URL** | GitHub repo path, Flatpak ID, APT package name, or URL | `flameshot-org/flameshot` |

**Examples:**
```text
Geany	Programming	Lightweight IDE	apt	apt	geany
CopyQ	Accessories	Advanced clipboard manager	AppImage	github	hluk/CopyQ
Dolphin	Games	GameCube/Wii emulator	flatpak	flatpak	org.DolphinEmu.dolphin-emu
```

### GitHub Token (Optional but Recommended)
To avoid GitHub API rate limits (60 requests/hour), you can generate a Personal Access Token:
1. Go to [GitHub Settings > Developer Settings > Personal Access Tokens](https://github.com/settings/tokens).
2. Generate a new token (no special scopes required).
3. Create a file named `token.txt` in the root directory of the project:
```bash
echo "ghp_YOUR_TOKEN_HERE" > token.txt
```
*Note: `token.txt` is ignored by `.gitignore` to keep your token safe.*

---

## 🗑️ Uninstall
Simply delete the application folder (`/Applications/AppName`) and its corresponding `.desktop` file in `~/.local/share/applications/`. Alternatively, use the built-in **`5. Remove`** menu in the script.

---

## 🤝 Contributing
Contributions are what make the open-source community such an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

## 📄 License
Distributed under the MIT License. See `LICENSE` for more information.

---
*Built with ❤️ for the Linux Community.*
```
