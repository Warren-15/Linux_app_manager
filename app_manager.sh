#!/bin/bash
# ==============================================================================
# APPLICATIONS MANAGER
# Run: sudo ./install_app.sh
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCES_DIR="$SCRIPT_DIR/sources"
DATA_DIR="$SCRIPT_DIR/data"
DOWNLOADS_DIR="$SCRIPT_DIR/Download"
ICONS_DIR="$SCRIPT_DIR/icons"

# Create directories
mkdir -p "$DOWNLOADS_DIR"
mkdir -p "$ICONS_DIR"
mkdir -p "$DATA_DIR"

APPLICATIONS_DIR="/Applications"
TEMP_DIR="/tmp/appmgr_$$"

# Detect real user
if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
    REAL_USER="$SUDO_USER"
    REAL_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
else
    REAL_USER="$USER"
    REAL_HOME="$HOME"
fi

DESKTOP_DIR="$REAL_HOME/.local/share/applications"
PROGRAM_LIST="$DATA_DIR/program list.txt"
SETTINGS_FILE="$DATA_DIR/settings.conf"

# Import modules in order
source "$SOURCES_DIR/colors.sh"
source "$SOURCES_DIR/utils.sh"
source "$SOURCES_DIR/categories.sh"
source "$SOURCES_DIR/icons.sh"
source "$SOURCES_DIR/shortcuts.sh"
source "$SOURCES_DIR/updates.sh"
source "$SOURCES_DIR/install.sh"
source "$SOURCES_DIR/remove.sh"
source "$SOURCES_DIR/settings.sh"

# Initialize directories (single block)
mkdir -p "$APPLICATIONS_DIR" 2>/dev/null
mkdir -p "$DESKTOP_DIR"
mkdir -p "$DATA_DIR"
mkdir -p "$DOWNLOADS_DIR"
mkdir -p "$ICONS_DIR"
mkdir -p "$TEMP_DIR"

# Fix ownership for user folders (when running as sudo)
if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
    chown -R "$SUDO_USER:$SUDO_USER" "$DOWNLOADS_DIR" 2>/dev/null
    chown -R "$SUDO_USER:$SUDO_USER" "$ICONS_DIR" 2>/dev/null
    chown -R "$SUDO_USER:$SUDO_USER" "$DATA_DIR" 2>/dev/null
    chmod -R 755 "$DOWNLOADS_DIR" 2>/dev/null
    chmod -R 755 "$ICONS_DIR" 2>/dev/null
fi

# DEBUG - remove after testing
echo "DESKTOP_DIR=$DESKTOP_DIR" > /tmp/app_debug.log
echo "REAL_HOME=$REAL_HOME" >> /tmp/app_debug.log
echo "REAL_USER=$REAL_USER" >> /tmp/app_debug.log
ls -la "$DESKTOP_DIR/" >> /tmp/app_debug.log 2>&1

# Clear cache on startup to ensure fresh load
rm -f /tmp/appmgr_program_cache_* /tmp/appmgr_program_mtime_*

# ==============================================================================
# MAIN MENU
# ==============================================================================

main_menu() {
    while true; do
        clear
        msg "╔══════════════════════════════════════════════╗" "$CYAN"
        msg "║        APPLICATIONS MANAGER                  ║" "$CYAN"
        msg "╚══════════════════════════════════════════════╝" "$CYAN"
        echo ""
        msg "  User: $REAL_USER" "$BLUE"
        echo ""
        echo -e "  Apps in /Applications: ${GREEN}$(ls -1 "$APPLICATIONS_DIR" 2>/dev/null | wc -l)${NC}"
        echo -e "  Desktop shortcuts:     ${GREEN}$(ls -1 "$DESKTOP_DIR"/*.desktop 2>/dev/null | wc -l)${NC}"
        echo ""
        msg "  ↳ Enter (empty) = Exit" "$YELLOW"
        echo ""
        echo "  0. Check for Updates / Download"
        echo "  1. Install (Queue)"
        echo "  2. Create / Edit Category"
        echo "  3. Create Shortcut"
        echo "  4. Edit Shortcuts"
        echo "  5. Remove"
        echo "  6. Settings"
        echo "  7. Exit"
        line
        echo ""
        printf "Choose (0-7, or press Enter to exit): "

        IFS= read -r input
        input=$(echo "$input" | tr -d '\r' | xargs)

        [ -z "$input" ] && { msg "Bye!" "$GREEN"; exit 0; }

        case "$input" in
            0) menu_updates ;;
            1) menu_install ;;
            2) menu_create_edit_category ;;
            3) menu_create_shortcut ;;
            4) menu_edit_shortcuts ;;
            5) remove_submenu ;;
            6) menu_settings ;;
            7|q|Q) msg "Bye!" "$GREEN"; exit 0 ;;
            *) msg "Invalid choice" "$RED"; sleep 1 ;;
        esac
    done
}
main_menu
