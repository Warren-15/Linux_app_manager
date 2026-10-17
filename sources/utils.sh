# ------------------------------------------------------------------------------
# GLOBAL VARIABLES
# ------------------------------------------------------------------------------

APPLICATIONS_DIR="/Applications"
TEMP_DIR="/tmp/appmgr_$$"

save_installed_version() {
    return 0
}

# Detect real user
if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
    REAL_USER="$SUDO_USER"
    REAL_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
else
    REAL_USER="$USER"
    REAL_HOME="$HOME"
fi

DESKTOP_DIR="$REAL_HOME/.local/share/applications"
CUSTOM_CAT_FILE="$REAL_HOME/.config/app_manager_categories.txt"
PROGRAM_LIST="$DATA_DIR/program list.txt"

# ------------------------------------------------------------------------------
# HELPERS
# ------------------------------------------------------------------------------

sanitize() {
    echo "$1" | sed 's/ /_/g' | sed 's/[^a-zA-Z0-9_.-]//g'
}

# ------------------------------------------------------------------------------
# app_name_from_file - Extract clean app name from filename
# ------------------------------------------------------------------------------
app_name_from_file() {
    local f="$1"
    local b="$(basename "$f")"
    
    # Remove ALL extensions
    b=$(echo "$b" | sed -E 's/\.(tar\.gz|tar\.xz|tar\.bz2|tgz|zip|7z|rar|AppImage|appimage)$//gi')
    b=$(echo "$b" | sed 's/\.[^.]*$//')
    
    # Remove architecture/OS markers
    b=$(echo "$b" | sed -E 's/[-_](Linux|linux|x86_64|X64|x64|amd64|win64|Win64|arm64|aarch64|armv7|armhf)//g')
    
    # Remove version patterns like _v4.7.2-stable or -v4.7.2
    b=$(echo "$b" | sed -E 's/[-_]v?[0-9]+\.[0-9]+(\.[0-9]+)?.*$//')
    b=$(echo "$b" | sed -E 's/[-_]stable.*$//gi')
    b=$(echo "$b" | sed -E 's/[-_]beta.*$//gi')
    b=$(echo "$b" | sed -E 's/[-_]rc[0-9]*.*$//gi')
    
    # Remove trailing separators
    b=$(echo "$b" | sed 's/[-_]*$//')
    
    # Replace separators with spaces, capitalize each word
    echo "$b" | sed 's/[-_]/ /g' | sed 's/\b\(.\)/\u\1/g' | sed 's/  */ /g' | sed 's/^ //' | sed 's/ $//'
}

desktop_value() {
    grep -m1 "^$2=" "$1" 2>/dev/null | cut -d= -f2-
}

extract_version() {
    local filename="$1"
    local base=$(echo "$filename" | sed 's/\.[^.]*$//')
    local version=$(echo "$base" | grep -oE '[-_][0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 | sed 's/^[-_]//')
    echo "$version"
}

# ------------------------------------------------------------------------------
# GET BASE NAME - Clean app name from version numbers & file extensions
# ------------------------------------------------------------------------------
get_base_name() {
    local name="$1"
    echo "$name" | \
        sed -E 's/\.(tar\.gz|tar\.xz|tar\.bz2|tgz|zip|AppImage|appimage|tar|deb|rpm|7z|rar)$//gi' | \
        sed -E 's/[0-9]+\.[0-9]+(\.[0-9]+)?//g' | \
        sed 's/SSE2//g' | \
        sed -E 's/[-_](Linux|linux|x86_64|X64|amd64|arm64|aarch64|armv7|armhf)//gi' | \
        sed 's/ (beta)//g' | \
        sed 's/ (stable)//g' | \
        sed 's/  */ /g' | \
        sed 's/^ //' | \
        sed 's/ $//'
}

# ------------------------------------------------------------------------------
# EXTRACT VERSION FROM NAME (fallback)
# ------------------------------------------------------------------------------
extract_version_from_name() {
    local name="$1"
    local version=$(echo "$name" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
    echo "$version"
}

# ==============================================================================
# FIND EXECUTABLE - Smart deep search
# ==============================================================================
find_executable() {
    local dir="$1"
    local folder_name=$(basename "$dir")
    local lower_folder=$(echo "$folder_name" | tr '[:upper:]' '[:lower:]')

    # ============================================================
    # STEP 1: Look for AppImage FIRST (highest priority)
    # Search entire tree
    # ============================================================
    local appimage=$(find "$dir" -type f \( -name "*.AppImage" -o -name "*.appimage" \) 2>/dev/null | head -1)
    if [ -n "$appimage" ]; then
        if [ ! -x "$appimage" ]; then
            chmod +x "$appimage" 2>/dev/null
        fi
        echo "$appimage"
        return
    fi

    # ============================================================
    # STEP 2: Smart search for executables (ELF/script)
    # ============================================================
    local best_match=""
    local best_score=0

    while IFS= read -r -d '' f; do
        local bn=$(basename "$f")
        local lower_bn=$(echo "$bn" | tr '[:upper:]' '[:lower:]')
        local ftype=$(file -b "$f" 2>/dev/null)

        # Skip libraries and non-executables
        [[ "$bn" == *.so ]] && continue
        [[ "$bn" == *.so.* ]] && continue
        [[ "$bn" == "chrome-sandbox" ]] && continue
        [[ "$bn" == *.desktop ]] && continue
        [[ "$bn" == *.txt ]] && continue
        [[ "$bn" == *.md ]] && continue
        [[ "$bn" == *.json ]] && continue
        [[ "$bn" == *.yml ]] && continue
        [[ "$bn" == *.yaml ]] && continue
        [[ "$bn" == *.png ]] && continue
        [[ "$bn" == *.svg ]] && continue
        [[ "$bn" == *.ico ]] && continue
        [[ "$ftype" != *"ELF"* ]] && [[ "$ftype" != *"script"* ]] && continue

        local score=0

        # Exact match with folder name
        if [ "$lower_bn" = "$lower_folder" ]; then
            score=200
        elif [[ "$lower_bn" == "$lower_folder"* ]]; then
            score=150
        elif [[ "$lower_bn" == *"$lower_folder"* ]]; then
            score=120
        elif [[ "$lower_folder" == *"$lower_bn"* ]] && [ ${#bn} -ge 3 ]; then
            score=100
        fi

        score=$((score + (100 - ${#bn})))
        [[ "$ftype" == *"ELF"* ]] && score=$((score + 30))

        if [[ "$lower_bn" == *"x86_64"* ]] || [[ "$lower_bn" == *"amd64"* ]]; then
            score=$((score + 20))
        elif [[ "$lower_bn" == *"i386"* ]] || [[ "$lower_bn" == *"i686"* ]]; then
            score=$((score - 20))
        fi

        local depth=$(echo "$f" | awk -F/ '{print NF}')
        local base_depth=$(echo "$dir" | awk -F/ '{print NF}')
        local relative_depth=$((depth - base_depth))
        score=$((score - relative_depth * 5))

        if [[ "$bn" =~ [0-9]+\.[0-9]+\.[0-9]+ ]]; then
            score=$((score - 10))
        fi

        if [[ "$f" == *"/."* ]] || [[ "$f" == *"/_"* ]]; then
            score=$((score - 30))
        fi

        if [ $score -gt $best_score ]; then
            best_score=$score
            best_match="$f"
        fi
    done < <(find "$dir" -type f -executable -print0 2>/dev/null)

    if [ -n "$best_match" ]; then
        echo "$best_match"
        return
    fi

    # ============================================================
    # STEP 3: Last resort - any executable file (even non-ELF)
    # ============================================================
    local fallback=$(find "$dir" -type f -executable 2>/dev/null | \
        grep -vE '\.(so|so\..*|txt|md|json|yml|yaml|png|svg|ico|desktop)$' | \
        head -1)

    if [ -n "$fallback" ]; then
        echo "$fallback"
        return
    fi

    echo ""
}

# ==============================================================================
# SMART FLATTEN - Remove unnecessary nesting from extracted archives
# ==============================================================================
smart_flatten() {
    local source_dir="$1"
    local target_dir="$2"
    local max_depth="${3:-7}"

    local current="$source_dir"
    local depth=0

    while [ $depth -lt $max_depth ]; do
        # List all items (including hidden) except "." and ".."
        local all_items=()
        while IFS= read -r -d '' item; do
            all_items+=("$item")
        done < <(find "$current" -maxdepth 1 -mindepth 1 -print0 2>/dev/null)

        local item_count=${#all_items[@]}

        # Empty → stop
        [ $item_count -eq 0 ] && break

        # Check if current level has executables (priority)
        local has_exec=0
        find "$current" -maxdepth 1 -type f -executable 2>/dev/null | grep -q . && has_exec=1
        find "$current" -maxdepth 1 -name "*.AppImage" 2>/dev/null | grep -q . && has_exec=1

        # If has executables → stop here (this is the real content)
        if [ $has_exec -eq 1 ]; then
            break
        fi

        # If single folder, decide whether to descend
        if [ $item_count -eq 1 ] && [ -d "${all_items[0]}" ]; then
            local folder_name=$(basename "${all_items[0]}")
            local lower_name=$(echo "$folder_name" | tr '[:upper:]' '[:lower:]')

            # Always descend into wrapper folders
            case "$lower_name" in
                -__w|-*|_*|build|dist|release|out|app|appimage|linux|bin|usr|opt|contents|squashfs-root|source|src|package|pkg)
                    current="${all_items[0]}"
                    depth=$((depth + 1))
                    continue
                    ;;
            esac

            # Not a wrapper: descend only if it contains executables deeper
            if find "${all_items[0]}" -maxdepth 3 -type f -executable 2>/dev/null | grep -q .; then
                current="${all_items[0]}"
                depth=$((depth + 1))
                continue
            fi
        fi

        # If multiple items but all are folders (no files), check if we should descend
        local files_count=0
        local dirs_count=0
        for item in "${all_items[@]}"; do
            [ -f "$item" ] && files_count=$((files_count + 1))
            [ -d "$item" ] && dirs_count=$((dirs_count + 1))
        done

        # Only subfolders (no files) → look for executables deeper
        if [ $files_count -eq 0 ] && [ $dirs_count -ge 1 ]; then
            local best_subfolder=""
            local best_score=0
            for subdir in "${all_items[@]}"; do
                [ ! -d "$subdir" ] && continue
                local exec_count=$(find "$subdir" -maxdepth 3 -type f -executable 2>/dev/null | wc -l)
                if [ "$exec_count" -gt $best_score ]; then
                    best_score=$exec_count
                    best_subfolder="$subdir"
                fi
            done

            if [ -n "$best_subfolder" ] && [ $best_score -gt 0 ]; then
                current="$best_subfolder"
                depth=$((depth + 1))
                continue
            fi
        fi

        # No reason to descend further
        break
    done

    # Copy all contents from current to target (including hidden files)
    if [ -d "$current" ]; then
        shopt -s dotglob
        cp -r "$current"/* "$target/" 2>/dev/null
        shopt -u dotglob
    fi

    return 0
}

extract_archive() {
    case "$1" in
        *.zip)    unzip -o "$1" -d "$2" >/dev/null 2>&1 ;;
        *.tar.gz|*.tgz)  tar xzf "$1" -C "$2" >/dev/null 2>&1 ;;
        *.tar.xz) tar xJf "$1" -C "$2" >/dev/null 2>&1 ;;
        *.tar.bz2) tar xjf "$1" -C "$2" >/dev/null 2>&1 ;;
        *.7z)     7z x "$1" -o"$2" -y >/dev/null 2>&1 ;;
        *.rar)    unrar x "$1" "$2" >/dev/null 2>&1 ;;
        *)        return 1 ;;
    esac
    return $?
}

# ------------------------------------------------------------------------------
# Check if app is REALLY installed (both .desktop AND folder exist)
# ------------------------------------------------------------------------------
is_app_installed() {
    local safe_name="$1"
    
    # Must have .desktop file
    [ -f "$DESKTOP_DIR/$safe_name.desktop" ] || return 1
    
    # Get the Path from desktop file
    local app_path=$(desktop_value "$DESKTOP_DIR/$safe_name.desktop" "Path")
    
    # Must have existing folder
    [ -n "$app_path" ] && [ -d "$app_path" ] && return 0
    
    # If Path is empty, check /Applications/safe_name
    [ -d "$APPLICATIONS_DIR/$safe_name" ] && return 0
    
    # Desktop file exists but app folder doesn't → orphan
    return 1
}

cleanup_empty_files() {
    local count=0
    for f in "$DOWNLOADS_DIR"/*; do
        [ -f "$f" ] || continue
        local size=$(stat -c %s "$f" 2>/dev/null || stat -f %z "$f" 2>/dev/null)
        if [ -z "$size" ] || [ "$size" -eq 0 ]; then
            rm -f "$f"
            count=$((count + 1))
        fi
    done
    [ $count -gt 0 ] && msg "  🗑️ Removed $count empty file(s)" "$YELLOW"
}

is_installable_file() {
    local f="$1"
    
    # Avoid temporary or harmful files
    [ "$(basename "$f")" = "install_app.sh" ] && return 1
    [[ "$(basename "$f")" == .* ]] && return 1
    [[ "$(basename "$f")" == *.sh ]] && return 1
    [[ "$(basename "$f")" == *.log ]] && return 1
    [[ "$(basename "$f")" == wget-log* ]] && return 1
    [[ "$(basename "$f")" == release ]] && return 1
    [[ "$(basename "$f")" == dl ]] && return 1
    [[ "$(basename "$f")" == latest-linux.yml ]] && return 1
    [[ "$(basename "$f")" == cosign.bundle ]] && return 1
    [[ "$(basename "$f")" == *.rpm ]] && return 1
    [[ "$(basename "$f")" == *.deb ]] && return 1
    [[ "$(basename "$f")" == *.ddeb ]] && return 1
    
    local lower=$(echo "$f" | tr '[:upper:]' '[:lower:]')
    case "$lower" in
        *.png|*.svg|*.ico|*.xpm|*.jpg|*.jpeg|*.gif|*.bmp|*.webp|*.tiff) return 1 ;;
        *.otf|*.ttf|*.woff|*.woff2) return 1 ;;
        *.txt|*.md|*.pdf|*.doc|*.docx|*.odt|*.yml) return 1 ;;
        *.mp3|*.wav|*.ogg|*.flac|*.aac|*.wma) return 1 ;;
        *.mp4|*.avi|*.mkv|*.mov|*.wmv|*.flv|*.webm) return 1 ;;
    esac
    
    # Check file size (ignore empty files)
    local size=$(stat -c %s "$f" 2>/dev/null || stat -f %z "$f" 2>/dev/null)
    if [ -n "$size" ] && [ "$size" -lt 1024 ]; then
        return 1
    fi
    
    return 0
}

# ------------------------------------------------------------------------------
# RUN AS ROOT - Get the proper command prefix
# ------------------------------------------------------------------------------
get_root_prefix() {
    if [ "$EUID" -eq 0 ]; then
        echo ""  # Already root
    elif command -v pkexec &>/dev/null; then
        echo "pkexec"
    elif command -v sudo &>/dev/null; then
        echo "sudo"
    else
        echo ""  # No way to elevate
    fi
}
