# ==============================================================================
# UPDATES & DOWNLOADS - PORTABLE LINUX (NO TOKEN REQUIRED)
# ==============================================================================
# Supports: github, flatpak, folder, direct
# Token is OPTIONAL - works anonymously (60 req/hour)
# ==============================================================================

# ------------------------------------------------------------------------------
# CONFIGURATION AND PATHS
# ------------------------------------------------------------------------------
if [ -z "$SCRIPT_DIR" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

if [ -z "$DATA_DIR" ]; then
    DATA_DIR="$SCRIPT_DIR/data"
fi
mkdir -p "$DATA_DIR"

PROGRAM_LIST="$DATA_DIR/program list.txt"
CACHE_DIR="$DATA_DIR/cache"
mkdir -p "$CACHE_DIR"

CACHE_TTL=21600   # 6 hours

# ==============================================================================
# TOKEN MANAGEMENT - OPTIONAL
# ==============================================================================
TOKEN_FILE="$SCRIPT_DIR/token.txt"

get_github_token() {
    if [ -n "$GITHUB_TOKEN" ]; then
        echo "$GITHUB_TOKEN"
        return 0
    fi

    if [ -f "$TOKEN_FILE" ] && [ -s "$TOKEN_FILE" ]; then
        local token=$(cat "$TOKEN_FILE" | tr -d '\r\n' | xargs)
        if [ -n "$token" ]; then
            echo "$token"
            return 0
        fi
    fi

    echo ""
    return 1
}

# ------------------------------------------------------------------------------
# COLORS AND MESSAGING (guard against redefinition)
# ------------------------------------------------------------------------------
[ -z "$RED" ] && RED='\033[1;31m'
[ -z "$GREEN" ] && GREEN='\033[1;32m'
[ -z "$YELLOW" ] && YELLOW='\033[1;33m'
[ -z "$BLUE" ] && BLUE='\033[1;34m'
[ -z "$CYAN" ] && CYAN='\033[1;36m'
[ -z "$NC" ] && NC='\033[0m'

if ! declare -f msg >/dev/null 2>&1; then
    msg() { echo -e "${2}${1}${NC}"; }
fi
if ! declare -f pause >/dev/null 2>&1; then
    pause() { echo ""; printf "Press Enter to continue..."; read dummy; }
fi
if ! declare -f line >/dev/null 2>&1; then
    line() { echo "══════════════════════════════════════════════════"; }
fi

# ------------------------------------------------------------------------------
# SMART CACHE MANAGEMENT
# ------------------------------------------------------------------------------
get_env_fingerprint() {
    echo "${USER}@${HOSTNAME}"
}

is_cache_valid() {
    local cache_file="$1"
    local fp_file="$CACHE_DIR/env_identity.id"
    local current_fp=$(get_env_fingerprint)

    if [ ! -f "$fp_file" ] || [ "$(cat "$fp_file")" != "$current_fp" ]; then
        rm -rf "$CACHE_DIR"/*
        mkdir -p "$CACHE_DIR"
        echo "$current_fp" > "$fp_file"
        return 1
    fi

    [ -f "$cache_file" ] || return 1

    local file_time=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null)
    local current_time=$(date +%s)
    local age=$((current_time - file_time))
    if [ $age -gt $CACHE_TTL ]; then
        rm -f "$cache_file"
        return 1
    fi

    if [ ! -s "$cache_file" ] || grep -q -i -E "(rate limit|not found|error|^\?$)" "$cache_file" 2>/dev/null; then
        rm -f "$cache_file"
        return 1
    fi

    return 0
}

# ==============================================================================
# SYSTEM ARCHITECTURE
# ==============================================================================
get_system_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64|amd64) echo "x86_64" ;;
        aarch64|arm64) echo "aarch64" ;;
        armv7l|armv7|armhf) echo "armv7" ;;
        armv6l) echo "armv6" ;;
        *) echo "$arch" ;;
    esac
}

get_target_architecture() {
    if [ "$ARCHITECTURE" = "auto" ] || [ -z "$ARCHITECTURE" ]; then
        get_system_arch
    else
        echo "$ARCHITECTURE"
    fi
}

# ==============================================================================
# GITHUB API REQUEST
# ==============================================================================
github_api_request() {
    local url="$1"
    local token=$(get_github_token)
    local headers=""

    if [ -n "$token" ]; then
        headers="Authorization: token $token"
    fi

    if [ -n "$headers" ]; then
        curl -s -H "$headers" -L --max-time 20 "$url" 2>/dev/null
    else
        curl -s -L --max-time 20 "$url" 2>/dev/null
    fi
}

# ==============================================================================
# GITHUB RATE LIMIT CHECK
# ==============================================================================
check_github_rate_limit() {
    local token=$(get_github_token)
    local headers=""

    if [ -n "$token" ]; then
        headers="Authorization: token $token"
    fi

    local response=$(curl -s -H "$headers" --max-time 10 "https://api.github.com/rate_limit" 2>/dev/null)

    if command -v jq &>/dev/null; then
        local remaining=$(echo "$response" | jq -r '.resources.core.remaining // 0')
        local limit=$(echo "$response" | jq -r '.resources.core.limit // 0')
        local reset=$(echo "$response" | jq -r '.resources.core.reset // 0')
        local reset_time=$(date -d "@$reset" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "unknown")

        if [ "$limit" = "0" ]; then
            echo "remaining=0"
            echo "limit=0"
            echo "reset=INVALID"
            return 1
        fi

        if [ -n "$remaining" ] && [ "$remaining" -gt 0 ]; then
            echo "remaining=$remaining"
            echo "limit=$limit"
            echo "reset=$reset_time"
            return 0
        else
            echo "remaining=0"
            echo "limit=$limit"
            echo "reset=$reset_time"
            return 1
        fi
    else
        local remaining=$(echo "$response" | grep -o '"remaining":[0-9]*' | head -1 | cut -d: -f2)
        if [ -n "$remaining" ] && [ "$remaining" -gt 0 ]; then
            echo "remaining=$remaining"
            echo "limit=60"
            return 0
        fi
        echo "remaining=0"
        return 1
    fi
}

# ==============================================================================
# DISPLAY TOKEN STATUS
# ==============================================================================
display_token_status() {
    local token=$(get_github_token)
    if [ -n "$token" ]; then
        local rate_info=$(check_github_rate_limit)
        local remaining=$(echo "$rate_info" | grep "remaining=" | cut -d= -f2)
        local limit=$(echo "$rate_info" | grep "limit=" | cut -d= -f2)
        local reset=$(echo "$rate_info" | grep "reset=" | cut -d= -f2)

        if [ "$limit" = "0" ] || [ "$reset" = "INVALID" ]; then
            msg "  ⚠ Token invalid - using anonymous (60 req/hour)" "$YELLOW"
        elif [ -n "$remaining" ] && [ "$remaining" -gt 0 ]; then
            msg "  ✓ Token OK (rate limit: $remaining / $limit)" "$GREEN"
        else
            msg "  ⚠ Token rate limit exhausted - reset at: $reset" "$YELLOW"
        fi
    else
        msg "  ℹ️  No token - using anonymous (60 requests/hour)" "$BLUE"
        msg "     (Optional: create token.txt for 5000 req/hour)" "$BLUE"
    fi
}

# ==============================================================================
# GET BASE NAME
# ==============================================================================
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

# ==============================================================================
# EXTRACT CURRENT VERSION (from .desktop file)
# ==============================================================================
extract_current_version() {
    local desktop_file="$1"
    local app_name="$2"
    local current_version=""

    # 1. From X-AppVersion
    current_version=$(grep -m1 '^X-AppVersion=' "$desktop_file" 2>/dev/null | cut -d= -f2- | sed 's/^v//' | sed 's/-.*//' | xargs)

    # 2. From AppImage filename in Exec
    if [ -z "$current_version" ] || [ "$current_version" = "Unknown" ] || [ "$current_version" = "?" ]; then
        local exec_cmd=$(grep -m1 '^Exec=' "$desktop_file" 2>/dev/null | cut -d= -f2-)
        exec_cmd=$(echo "$exec_cmd" | sed 's/^pkexec //' | sed 's/^sudo //')
        local exec_file=$(echo "$exec_cmd" | awk '{print $1}')
        if [[ "$exec_file" == *".AppImage"* ]] || [[ "$exec_file" == *".appimage"* ]]; then
            local filename=$(basename "$exec_file")
            local versions=$(echo "$filename" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | sort -V)
            current_version=$(echo "$versions" | tail -1)
        fi
    fi

    # 3. From installation Path
    if [ -z "$current_version" ]; then
        local exec_path=$(grep -m1 '^Path=' "$desktop_file" 2>/dev/null | cut -d= -f2-)
        if [ -n "$exec_path" ] && [ -d "$exec_path" ]; then
            local folder_name=$(basename "$exec_path")
            current_version=$(echo "$folder_name" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
        fi
    fi

    # 4. From app name itself
    if [ -z "$current_version" ]; then
        current_version=$(echo "$app_name" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
    fi

    # Clean up
    if [ -n "$current_version" ]; then
        current_version=$(echo "$current_version" | sed 's/^v//' | sed 's/-.*//' | sed 's/\.$//' | xargs)
    fi

    [ -z "$current_version" ] && current_version="?"
    echo "$current_version"
}

# ==============================================================================
# GET LATEST VERSION FROM GITHUB (with smart fallbacks for tricky repos)
# ==============================================================================
get_latest_version_from_github() {
    local repo="$1"
    local app_safe_name=$(echo "$repo" | sed 's/\//_/g')
    local cache_file="$CACHE_DIR/${app_safe_name}.version.cache"

    if is_cache_valid "$cache_file"; then
        cat "$cache_file"
        return 0
    fi

    local tag=""

    # Attempt 1: releases/latest
    local api_url="https://api.github.com/repos/$repo/releases/latest"
    local response=$(github_api_request "$api_url")

    if [ -n "$response" ] && ! echo "$response" | grep -q -i "rate limit"; then
        if command -v jq &>/dev/null; then
            tag=$(echo "$response" | jq -r '.tag_name // empty' 2>/dev/null)
        fi
    fi

    # Attempt 2: releases list (first non-prerelease)
    if [ -z "$tag" ]; then
        local releases_url="https://api.github.com/repos/$repo/releases?per_page=30"
        local releases_resp=$(github_api_request "$releases_url")
        if command -v jq &>/dev/null; then
            tag=$(echo "$releases_resp" | jq -r '.[] | select(.prerelease == false and .draft == false) | .tag_name' 2>/dev/null | head -1)
        fi
    fi

    # Attempt 3: TAGS API (fallback)
    if [ -z "$tag" ]; then
        local tags_url="https://api.github.com/repos/$repo/tags?per_page=100"
        local tags_resp=$(github_api_request "$tags_url")

        if command -v jq &>/dev/null; then
            local all_tags=$(echo "$tags_resp" | jq -r '.[].name' 2>/dev/null)

            if [ -n "$all_tags" ]; then
                local repo_name=$(echo "$repo" | cut -d'/' -f2)

                # Pattern A: prefixed version (Audacity-4.0.1)
                tag=$(echo "$all_tags" | grep -iE "^${repo_name}[-_]v?[0-9]+\.[0-9]+" | \
                    grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | sort -V | tail -1)

                # Pattern B: clean semantic (v1.2.3 or 1.2.3)
                if [ -z "$tag" ]; then
                    tag=$(echo "$all_tags" | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | \
                        sed 's/^v//' | sort -V | tail -1)
                fi

                # Pattern C: version with prefix (release-5.6.2)
                if [ -z "$tag" ]; then
                    tag=$(echo "$all_tags" | grep -oE 'v?\.?[0-9]+\.[0-9]+\.[0-9]+' | \
                        sed 's/^v//' | sed 's/^\.//' | sort -V | tail -1)
                fi

                # Pattern D: build number (v0.1-11894)
                if [ -z "$tag" ]; then
                    tag=$(echo "$all_tags" | grep -oE 'v?[0-9]+\.[0-9]+-[0-9]+' | \
                        sed 's/^v//' | sort -t- -k2 -n | tail -1)
                fi

                # Pattern E: X.Y (2 parts)
                if [ -z "$tag" ]; then
                    tag=$(echo "$all_tags" | grep -E '^v?[0-9]+\.[0-9]+$' | \
                        sed 's/^v//' | sort -V | tail -1)
                fi

                # Pattern F: any X.Y.Z anywhere
                if [ -z "$tag" ]; then
                    tag=$(echo "$all_tags" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | \
                        sort -V | tail -1)
                fi

                # Pattern G: any X.Y anywhere
                if [ -z "$tag" ]; then
                    tag=$(echo "$all_tags" | grep -oE '[0-9]+\.[0-9]+' | \
                        sort -V | tail -1)
                fi
            fi
        fi
    fi

    # Clean and validate
    if [ -n "$tag" ]; then
        local cleaned=$(echo "$tag" | sed 's/^v//' | sed 's/^\.//' | grep -oE '^[0-9]+\.[0-9]+(\.[0-9]+)?(-[0-9]+)?')

        if [ -n "$cleaned" ] && [[ "$cleaned" =~ ^[0-9]+\.[0-9] ]]; then
            echo "$cleaned" > "$cache_file"
            echo "$cleaned"
            return 0
        fi
    fi

    echo ""
}

# ==============================================================================
# GET LATEST VERSION FROM FLATPAK
# ==============================================================================
get_latest_version_from_flatpak() {
    local app_id="$1"
    local cache_file="$CACHE_DIR/flatpak_${app_id//./_}.cache"

    if is_cache_valid "$cache_file"; then
        cat "$cache_file"
        return 0
    fi

    local api_url="https://flathub.org/api/v2/appstream/${app_id}"
    local response=$(curl -s -L --max-time 15 "$api_url" 2>/dev/null)

    local version=""
    if command -v jq &>/dev/null; then
        version=$(echo "$response" | jq -r '.releases[0].version // .version // empty' 2>/dev/null)
    else
        version=$(echo "$response" | grep -oE '"version"\s*:\s*"[^"]*"' | head -1 | sed 's/.*"version"\s*:\s*"//;s/"//')
    fi

    version=$(echo "$version" | sed 's/^v//' | sed 's/-.*//' | xargs)

    if [ -n "$version" ] && [[ "$version" =~ ^[0-9]+\.[0-9] ]]; then
        echo "$version" > "$cache_file"
        echo "$version"
        return 0
    fi

    # Fallback: old Flathub API
    local alt_url="https://flathub.org/api/v1/apps/${app_id}"
    local alt_response=$(curl -s -L --max-time 15 "$alt_url" 2>/dev/null)
    if command -v jq &>/dev/null; then
        version=$(echo "$alt_response" | jq -r '.releases[0].version // empty' 2>/dev/null)
    fi
    version=$(echo "$version" | sed 's/^v//' | xargs)

    if [ -n "$version" ] && [[ "$version" =~ ^[0-9]+\.[0-9] ]]; then
        echo "$version" > "$cache_file"
        echo "$version"
        return 0
    fi

    echo ""
}

# ==============================================================================
# GET LATEST VERSION FROM FOLDER
# ==============================================================================
get_latest_version_from_folder() {
    local base_url="$1"
    local app_name="$2"
    local cache_file="$CACHE_DIR/folder_$(echo "$base_url" | sed 's/[^a-zA-Z0-9]/_/g').cache"

    if is_cache_valid "$cache_file"; then
        cat "$cache_file"
        return 0
    fi

    local page=$(curl -sL --max-time 20 "$base_url" 2>/dev/null)
    if [ -z "$page" ]; then
        echo ""
        return
    fi

    local version=""

    version=$(echo "$page" | grep -oE 'href="[0-9]+\.[0-9]+(\.[0-9]+)?/"' | sed 's/href="//;s/"//;s/\///' | sort -V | tail -1)

    if [ -z "$version" ]; then
        version=$(echo "$page" | grep -oE 'href="v[0-9]+\.[0-9]+(\.[0-9]+)?/"' | sed 's/href="//;s/"//;s/\///' | sed 's/^v//' | sort -V | tail -1)
    fi

    # Blender
    if [ -z "$version" ] && [[ "$app_name" == *"Blender"* ]]; then
        version=$(echo "$page" | grep -oE 'href="Blender[0-9]+\.[0-9]+/"' | sed 's/href="//;s/"//;s/\///' | sed 's/Blender//' | sort -V | tail -1)
    fi

    # GIMP
    if [ -z "$version" ] && [[ "$app_name" == *"GIMP"* ]]; then
        version=$(echo "$page" | grep -oE 'href="v[0-9]+\.[0-9]+/"' | sed 's/href="//;s/"//;s/\///' | sed 's/^v//' | sort -V | tail -1)
    fi

    # tinyMediaManager
    if [ -z "$version" ] && [[ "$app_name" == *"tinyMediaManager"* ]]; then
        version=$(echo "$page" | grep -oE 'tinymediamanager[^"]*[0-9]+\.[0-9]+\.[0-9]+' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -1)
    fi

    if [ -z "$version" ]; then
        version=$(echo "$page" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -1)
    fi

    if [ -n "$version" ] && [[ "$version" =~ ^[0-9]+\.[0-9] ]]; then
        echo "$version" > "$cache_file"
        echo "$version"
        return 0
    fi

    echo ""
}

# ==============================================================================
# GET VERSION FROM URL (dispatcher)
# ==============================================================================
get_latest_version_from_url() {
    local url="$1"
    local app_name="$2"
    local source="$3"

    [ -z "$url" ] && { echo ""; return; }

    # ============================================================
    # APT source - get installed version
    # ============================================================
    if [[ "$source" == "apt" ]]; then
        local pkg="$url"
        local installed=$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null)
        local available=$(apt-cache policy "$pkg" 2>/dev/null | grep "Candidate:" | awk '{print $2}')
        if [ -n "$available" ] && [ "$available" != "(none)" ]; then
            echo "$available"
        else
            echo "$installed"
        fi
        return
    fi

    # ============================================================
    # GitHub
    # ============================================================
    if [[ "$source" == "github" ]] || [[ "$url" == *"github.com"* ]]; then
        local repo="$url"
        if [[ "$url" == *"github.com"* ]]; then
            repo=$(echo "$url" | sed 's|https://github.com/||' | sed 's|/releases.*||' | sed 's|/$||')
        fi
        get_latest_version_from_github "$repo"
        return
    fi

    # ============================================================
    # Flatpak
    # ============================================================
    if [[ "$source" == "flatpak" ]]; then
        get_latest_version_from_flatpak "$url"
        return
    fi

    # ============================================================
    # Folder
    # ============================================================
    if [[ "$source" == "folder" ]]; then
        get_latest_version_from_folder "$url" "$app_name"
        return
    fi

    # ============================================================
    # Direct
    # ============================================================
    if [[ "$source" == "direct" ]]; then
        echo ""
        return
    fi

    echo ""
}

# ==============================================================================
# CONSTRUCT DOWNLOAD URL
# ==============================================================================
construct_download_url() {
    local source="$1"
    local repo_or_url="$2"
    local app_name="$3"
    local format="$4"
    local version="$5"
    local download_hint="$6"
    
     # ============================================================
    # APT source
    # ============================================================
    if [[ "$source" == "apt" ]]; then
        echo "apt:$repo_or_url"
        return 0
    fi

    if [[ "$source" == "direct" ]]; then
        echo "$repo_or_url"
        return 0
    fi

    if [[ "$source" == "flatpak" ]]; then
        echo "flatpak:$repo_or_url"
        return 0
    fi

    if [[ "$source" == "github" ]]; then
        local repo="$repo_or_url"
        if [[ "$repo_or_url" == *"github.com"* ]]; then
            repo=$(echo "$repo_or_url" | sed 's|https://github.com/||' | sed 's|/releases.*||' | sed 's|/$||')
        fi
        repo=$(echo "$repo" | sed 's/^\/\///' | sed 's/\/$//')

        local real_url=$(get_github_download_url "$repo" "$app_name" "$format" "$download_hint")
        if [ -n "$real_url" ]; then
            echo "$real_url"
            return 0
        fi

        echo ""
        return 1
    fi

    if [[ "$source" == "folder" ]]; then
        local base_url="$repo_or_url"
        local page=$(curl -sL --max-time 20 "$base_url" 2>/dev/null)

        # tinyMediaManager
        if [[ "$app_name" == *"tinyMediaManager"* ]]; then
            local download_page=$(curl -sL --max-time 20 "https://www.tinymediamanager.org/download/" 2>/dev/null)
            local download_link=$(echo "$download_page" | grep -oE 'href="[^"]*tinymediamanager[^"]*\.tar\.gz"' | head -1 | sed 's/href="//' | sed 's/"//')
            if [ -n "$download_link" ]; then
                if [[ "$download_link" == http* ]]; then
                    echo "$download_link"
                else
                    echo "https://www.tinymediamanager.org${download_link}"
                fi
                return
            fi
        fi

        # Blender
        if [[ "$app_name" == *"Blender"* ]]; then
            local version_folder=$(echo "$page" | grep -oE 'href="Blender[0-9]+\.[0-9]+/"' | sed 's/href="//;s/"//;s/\///' | sort -V | tail -1)
            if [ -n "$version_folder" ]; then
                local version_page=$(curl -sL --max-time 20 "${base_url}${version_folder}/" 2>/dev/null)
                local appimage_file=$(echo "$version_page" | grep -oE 'href="[^"]*linux-x64[^"]*\.AppImage"' | sed 's/href="//;s/"//' | head -1)
                if [ -n "$appimage_file" ]; then
                    echo "${base_url}${version_folder}/${appimage_file}"
                    return
                fi
                local tar_file=$(echo "$version_page" | grep -oE 'href="[^"]*\.tar\.xz"' | sed 's/href="//;s/"//' | head -1)
                if [ -n "$tar_file" ]; then
                    echo "${base_url}${version_folder}/${tar_file}"
                    return
                fi
            fi
        fi

        # GIMP
        if [[ "$app_name" == *"GIMP"* ]] || [[ "$app_name" == *"gimp"* ]]; then
            local version_folders=$(echo "$page" | grep -oE 'href="v[0-9]+\.[0-9]+(\.[0-9]+)?/"' | sed 's/href="//;s/"//;s/\///' | sort -V | tail -1)
            if [ -n "$version_folders" ]; then
                local version_page=$(curl -sL --max-time 20 "${base_url}${version_folders}/" 2>/dev/null)
                local file=$(echo "$version_page" | grep -oE 'href="[^"]*\.(AppImage|tar\.bz2|tar\.xz)"' | sed 's/href="//;s/"//' | grep -i "linux" | head -1)
                if [ -n "$file" ]; then
                    echo "${base_url}${version_folders}/${file}"
                    return
                fi
            fi
            echo "https://download.gimp.org/mirror/pub/gimp/v2.10/gimp-2.10.38.tar.bz2"
            return
        fi

        # Generic
        local patterns=("\.AppImage" "\.appimage" "\.tar\.gz" "\.tar\.xz" "\.zip" "\.tar\.bz2")
        local best=""

        for pattern in "${patterns[@]}"; do
            local files=$(echo "$page" | grep -ioE "href=\"[^\"]*${pattern}[^\"]*\"" | sed 's/href="//' | sed 's/"//' | grep -vE '\.(sha|sig|asc|digest|checksum)')

            local absolute_urls=""
            while IFS= read -r file; do
                [ -z "$file" ] && continue
                if ! echo "$file" | grep -qi "linux\|x86_64\|amd64"; then
                    continue
                fi
                if [[ "$file" == http* ]]; then
                    absolute_urls="${absolute_urls}${file}\n"
                elif [[ "$file" == /* ]]; then
                    local domain=$(echo "$base_url" | sed 's#^\(https\?://[^/]*\).*#\1#')
                    absolute_urls="${absolute_urls}${domain}${file}\n"
                else
                    absolute_urls="${absolute_urls}${base_url}${file}\n"
                fi
            done <<< "$files"

            local selected=$(echo -e "$absolute_urls" | grep -i "appimage" | grep -vi "arm\|aarch" | head -1)
            [ -z "$selected" ] && selected=$(echo -e "$absolute_urls" | grep -i "x86_64\|amd64" | head -1)
            [ -z "$selected" ] && selected=$(echo -e "$absolute_urls" | head -1)

            if [ -n "$selected" ]; then
                best="$selected"
                break
            fi
        done

        echo "$best"
        return
    fi

    echo ""
}

# ==============================================================================
# GITHUB API - GET REAL DOWNLOAD URL
# ==============================================================================
get_github_download_url() {
    local repo="$1"
    local app_name="$2"
    local format="$3"
    local download_hint="$4"

    repo=$(echo "$repo" | sed 's|https://github.com/||' | sed 's|/releases.*||' | sed 's|/$||')
    repo=$(echo "$repo" | sed 's/^\/\///' | sed 's/\/$//')

    local cache_file="$CACHE_DIR/github_$(echo "$repo" | sed 's|/|_|g')"
    local release_json=""
    local all_assets=""

    if [ -f "$cache_file" ] && is_cache_valid "$cache_file" && [ -s "$cache_file" ]; then
        release_json=$(cat "$cache_file")
        if command -v jq &>/dev/null; then
            all_assets=$(echo "$release_json" | jq -r '.assets[].browser_download_url' 2>/dev/null)
        fi
    fi

    if [ -z "$all_assets" ] || [ "$all_assets" = "null" ]; then
        local api_url="https://api.github.com/repos/$repo/releases/latest"
        local response=$(github_api_request "$api_url")

        if echo "$response" | grep -q '"message": "Not Found"' || echo "$response" | grep -q '"prerelease": true'; then
            local releases_url="https://api.github.com/repos/$repo/releases?per_page=20"
            local releases_data=$(github_api_request "$releases_url")
            if command -v jq &>/dev/null; then
                response=$(echo "$releases_data" | jq -r '.[] | select(.prerelease == false and .draft == false and .assets | length > 0) | .' 2>/dev/null | head -1)
            fi
        fi

        release_json="$response"
        if command -v jq &>/dev/null; then
            all_assets=$(echo "$release_json" | jq -r '.assets[].browser_download_url' 2>/dev/null)
        fi

        if [ -n "$release_json" ] && ! echo "$release_json" | grep -q "rate limit"; then
            echo "$release_json" > "$cache_file"
        fi
    fi

    if [ -z "$all_assets" ] || [ "$all_assets" = "null" ]; then
        local releases_url="https://api.github.com/repos/$repo/releases?per_page=20"
        local releases_data=$(github_api_request "$releases_url")
        if command -v jq &>/dev/null; then
            local release_with_assets=$(echo "$releases_data" | jq -r '.[] | select(.assets | length > 0) | .' 2>/dev/null | head -1)
            all_assets=$(echo "$release_with_assets" | jq -r '.assets[].browser_download_url' 2>/dev/null)
        fi
    fi

    if [ -z "$all_assets" ] || [ "$all_assets" = "null" ]; then
        echo ""
        return 1
    fi

    local target_arch=$(get_target_architecture)

    local preferred_formats=()
    case "$format" in
        "AppImage") preferred_formats+=("appimage" "AppImage") ;;
        "tar.gz") preferred_formats+=("tar.gz" "tgz") ;;
        "tar.xz") preferred_formats+=("tar.xz" "txz") ;;
        "zip") preferred_formats+=("zip") ;;
        "tar.bz2") preferred_formats+=("tar.bz2" "tbz2") ;;
        *) preferred_formats+=("appimage" "tar.gz" "tar.xz" "zip" "tar.bz2") ;;
    esac

    local all_formats=("appimage" "AppImage" "tar.gz" "tgz" "tar.xz" "txz" "zip" "tar.bz2" "tbz2")

    local best_url=""
    local best_score=-9999
    local app_clean=$(echo "$app_name" | tr '[:upper:]' '[:lower:]' | sed 's/ //g' | sed 's/[^a-z0-9]//g')
    local app_short=$(echo "$app_clean" | cut -c1-6)

    while IFS= read -r url; do
        [ -z "$url" ] && continue
        local filename=$(basename "$url")
        local lower=$(echo "$filename" | tr '[:upper:]' '[:lower:]')
        local score=0

        local format_score=0
        for fmt in "${preferred_formats[@]}"; do
            if echo "$lower" | grep -q "$fmt"; then
                format_score=500
                break
            fi
        done
        if [ $format_score -eq 0 ]; then
            local portable_match=0
            for fmt in "${all_formats[@]}"; do
                if echo "$lower" | grep -q "$fmt"; then
                    portable_match=1
                    score=$((score + 200))
                    break
                fi
            done
            if [ $portable_match -eq 0 ]; then
                continue
            fi
        else
            score=$((score + format_score))
        fi

        case "$target_arch" in
            "x86_64")
                if echo "$lower" | grep -q "x86_64\|amd64"; then
                    score=$((score + 300))
                elif echo "$lower" | grep -q "arm64\|aarch64\|armv7\|armhf"; then
                    score=$((score - 1000))
                fi
                ;;
            "aarch64"|"arm64")
                if echo "$lower" | grep -q "arm64\|aarch64"; then
                    score=$((score + 300))
                elif echo "$lower" | grep -q "x86_64\|amd64"; then
                    score=$((score - 1000))
                fi
                ;;
            "armv7")
                if echo "$lower" | grep -q "armv7\|armhf"; then
                    score=$((score + 300))
                elif echo "$lower" | grep -q "x86_64\|amd64\|arm64\|aarch64"; then
                    score=$((score - 1000))
                fi
                ;;
        esac

        if echo "$lower" | grep -q "linux"; then
            score=$((score + 200))
        elif echo "$lower" | grep -q "windows\|win\|macos\|darwin\|osx"; then
            score=$((score - 500))
        fi

        local name_clean=$(echo "$filename" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')
        if echo "$name_clean" | grep -q "$app_clean"; then
            score=$((score + 150))
        elif [ ${#app_short} -gt 3 ] && echo "$name_clean" | grep -q "$app_short"; then
            score=$((score + 80))
        fi

        if [ -n "$download_hint" ]; then
            local hint_lower=$(echo "$download_hint" | tr '[:upper:]' '[:lower:]')
            if echo "$lower" | grep -q "$hint_lower"; then
                score=$((score + 1000))
            fi
        fi

        if echo "$lower" | grep -q "debug\|dbg\|symbol\|test\|unstable\|src\|source"; then
            score=$((score - 2000))
        fi
        if echo "$lower" | grep -q "\.deb\|\.rpm\|\.pkg\|\.msi\|\.exe\|\.dmg\|\.flatpak\|\.snap"; then
            score=$((score - 1000))
        fi

        if [ $score -gt $best_score ]; then
            best_score=$score
            best_url="$url"
        fi
    done <<< "$all_assets"

    if [ -n "$best_url" ]; then
        echo "$best_url"
        return 0
    fi

    echo ""
    return 1
}

# ==============================================================================
# VERSION COMPARISON
# ==============================================================================
version_is_newer() {
    local latest=$(echo "$1" | sed 's/^v//' | sed 's/-.*//' | sed 's/[^0-9.]//g')
    local current=$(echo "$2" | sed 's/^v//' | sed 's/-.*//' | sed 's/[^0-9.]//g')

    [ -z "$current" ] || [ "$current" = "?" ] && return 0
    [ -z "$latest" ] && return 1
    [ "$latest" = "$current" ] && return 1

    local highest=$(printf '%s\n%s\n' "$current" "$latest" | sort -V | tail -1)

    if [ "$highest" = "$latest" ] && [ "$latest" != "$current" ]; then
        return 0
    else
        return 1
    fi
}

# ==============================================================================
# DISPLAY VERSION INFO
# ==============================================================================
display_version_info() {
    local app_name="$1"
    local current="$2"
    local latest="$3"

    if [ "$current" = "?" ] || [ "$current" = "Unknown" ]; then
        if [ -z "$latest" ] || [ "$latest" = "?" ]; then
            echo -e "  ${app_name}: ${YELLOW}?${NC} (unknown)"
        else
            echo -e "  ${app_name}: ${YELLOW}?${NC} → ${GREEN}${latest}${NC}"
        fi
    elif [ -z "$latest" ] || [ "$latest" = "?" ]; then
        echo -e "  ${app_name}: ${BLUE}${current}${NC} (latest unknown)"
    elif [ "$current" = "$latest" ]; then
        echo -e "  ${app_name}: ${GREEN}✓ ${current} (latest)${NC}"
    elif version_is_newer "$latest" "$current"; then
        echo -e "  ${app_name}: ${YELLOW}${current}${NC} → ${GREEN}${latest}${NC}"
    else
        echo -e "  ${app_name}: ${GREEN}${current}${NC} (newer than remote ${latest})"
    fi
}

# ==============================================================================
# LOAD PROGRAM LIST
# ==============================================================================
load_program_list() {
    PROG_NAMES=()
    PROG_CATEGORIES=()
    PROG_DESCRIPTIONS=()
    PROG_FORMATS=()
    PROG_SOURCES=()
    PROG_VERSIONS=()
    PROG_URLS=()
    PROG_HINTS=()

    if [ ! -f "$PROGRAM_LIST" ]; then
        msg "  Program list file not found: $PROGRAM_LIST" "$YELLOW"
        return
    fi

    local raw_data
    raw_data=$(awk -F '\t' '!/^[[:space:]]*#/ && NF>=6 {printf "%s|%s|%s|%s|%s|%s|%s\n", $1, $2, $3, $4, $5, $6, $7}' "$PROGRAM_LIST")

    while IFS='|' read -r name cat desc fmt src url hint; do
        name=$(echo "$name" | xargs)
        cat=$(echo "$cat" | xargs)
        desc=$(echo "$desc" | xargs)
        fmt=$(echo "$fmt" | xargs)
        src=$(echo "$src" | xargs)
        url=$(echo "$url" | xargs)
        hint=$(echo "$hint" | xargs)

        [ -z "$name" ] && continue
        [ -z "$url" ] && continue

        [ -z "$fmt" ] && fmt="AppImage"
        [ -z "$src" ] && src="github"

        PROG_NAMES+=("$name")
        PROG_CATEGORIES+=("$cat")
        PROG_DESCRIPTIONS+=("$desc")
        PROG_FORMATS+=("$fmt")
        PROG_SOURCES+=("$src")
        PROG_URLS+=("$url")
        PROG_HINTS+=("$hint")
        PROG_VERSIONS+=("")
    done <<< "$raw_data"

    if [ ${#PROG_NAMES[@]} -eq 0 ]; then
        msg "  No valid entries found in $PROGRAM_LIST" "$RED"
    else
        msg "  Loaded ${#PROG_NAMES[@]} programs from list." "$GREEN"
    fi
}

# ==============================================================================
# INSTALL SINGLE - Fallback (only used if install.sh not loaded)
# ==============================================================================
# The real install_single is defined in sources/install.sh
# This is only a safety net in case install.sh is not loaded.

if ! declare -f install_single >/dev/null 2>&1; then
    install_single() {
        msg "  ✗ install_single not loaded (install.sh missing?)" "$RED"
        return 1
    }
fi

# ==============================================================================
# DOWNLOAD FILE
# ==============================================================================
download_file() {
    local url="$1"
    local dest="$2"
    local name="$3"
    local filename=$(basename "$dest")
    msg "  Downloading $name ($filename)..." "$BLUE"

    if [ -z "$url" ]; then
        msg "  ✗ No download URL" "$RED"
        return 1
    fi

    echo "0" > /tmp/dl_choice_$$
    trap 'echo ""; echo "  1. Skip this download"; echo "  2. Cancel ALL remaining"; printf "  Select: "; IFS= read -r c; echo "$c" > /tmp/dl_choice_$$' INT

    if command -v wget &>/dev/null; then
        (cd "$DOWNLOADS_DIR" && wget -c -q --show-progress --progress=bar:force:noscroll -O "$filename" "$url") 2>&1
    elif command -v curl &>/dev/null; then
        (cd "$DOWNLOADS_DIR" && curl -C - -# -L -o "$filename" "$url") 2>&1
    fi

    trap - INT
    local user_choice=$(cat /tmp/dl_choice_$$ 2>/dev/null)
    rm -f /tmp/dl_choice_$$

    if [ "$user_choice" = "2" ]; then
        msg "  ✗ Cancelled ALL remaining" "$RED"
        rm -f "$dest" 2>/dev/null
        return 3
    fi
    if [ "$user_choice" = "1" ]; then
        msg "  ⤏ Skipped" "$YELLOW"
        rm -f "$dest" 2>/dev/null
        return 2
    fi

    if [ -f "$dest" ] && [ -s "$dest" ]; then
        local size=$(stat -c %s "$dest" 2>/dev/null)
        local size_mb=$((size / 1048576))
        if [ $size_mb -gt 0 ]; then
            msg "  ✓ Downloaded (${size_mb} MB)" "$GREEN"
        else
            local size_kb=$((size / 1024))
            if [ $size_kb -gt 0 ]; then
                msg "  ✓ Downloaded (${size_kb} KB)" "$GREEN"
            else
                msg "  ✓ Downloaded ($size bytes)" "$GREEN"
            fi
        fi
        return 0
    fi

    rm -f "$dest" 2>/dev/null
    msg "  ✗ Download failed" "$RED"
    return 2
}

# ==============================================================================
# DUMMY FUNCTIONS FOR COMPATIBILITY
# ==============================================================================
if ! declare -f list_shortcuts >/dev/null 2>&1; then
    list_shortcuts() {
        find "$DESKTOP_DIR" -maxdepth 1 -name "*.desktop" 2>/dev/null | sort
    }
fi

if ! declare -f desktop_value >/dev/null 2>&1; then
    desktop_value() {
        grep -m1 "^$2=" "$1" 2>/dev/null | cut -d= -f2-
    }
fi

if ! declare -f update_db >/dev/null 2>&1; then
    update_db() {
        update-desktop-database "$DESKTOP_DIR" 2>/dev/null
        command -v xdg-desktop-menu &>/dev/null && xdg-desktop-menu forceupdate 2>/dev/null
        command -v kbuildsycoca5 &>/dev/null && kbuildsycoca5 2>/dev/null
    }
fi

# ==============================================================================
# CHECK FOR UPDATES
# ==============================================================================
menu_check_updates() {
    clear
    msg "===== CHECK FOR UPDATES =====" "$CYAN"
    line
    echo ""

    display_token_status
    echo ""

    load_program_list

    if [ ${#PROG_NAMES[@]} -eq 0 ]; then
        msg "  Program list not found or empty (tried: $PROGRAM_LIST)" "$YELLOW"
        pause
        return
    fi

    local all_shortcuts=()
    while IFS= read -r df; do
        [ -z "$df" ] && continue
        all_shortcuts+=("$df")
    done < <(list_shortcuts)

    local our_apps=()
    for df in "${all_shortcuts[@]}"; do
        local ex=$(desktop_value "$df" "Exec")
        ex=$(echo "$ex" | sed 's/^pkexec //' | sed 's/^sudo //')
        local pa=$(desktop_value "$df" "Path")
        if [[ "$ex" == "$APPLICATIONS_DIR/"* ]] || [[ "$pa" == "$APPLICATIONS_DIR/"* ]]; then
            our_apps+=("$df")
        fi
    done

    # Deduplicate by base name (case-insensitive)
    declare -A seen_bases
    local deduped=()
    for df in "${our_apps[@]}"; do
        local nm=$(desktop_value "$df" "Name")
        local base=$(get_base_name "$nm")
        local base_lower=$(echo "$base" | tr '[:upper:]' '[:lower:]')
        if [ -z "${seen_bases[$base_lower]}" ]; then
            seen_bases[$base_lower]="$df"
            deduped+=("$df")
        fi
    done
    our_apps=("${deduped[@]}")

    if [ ${#our_apps[@]} -eq 0 ]; then
        msg "  No apps found in $APPLICATIONS_DIR" "$YELLOW"
        pause
        return
    fi

    msg "  Found ${#our_apps[@]} installed app(s) to check" "$BLUE"
    echo ""

    local updates=()
    local update_names=()
    local update_current=()
    local update_latest=()
    local update_urls=()
    local update_sources=()
    local update_formats=()
    local update_hints=()
    local up_to_date=0
    local unknown=0

    for df in "${our_apps[@]}"; do
        local nm=$(desktop_value "$df" "Name")
        [ -z "$nm" ] && continue

        local current_version=$(extract_current_version "$df" "$nm")
        local base_name=$(get_base_name "$nm")
        local base_name_clean=$(echo "$base_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')

        local list_url=""
        local list_source=""
        local list_format=""
        local list_hint=""
        local found=0
        local best_match_score=0

        for i in "${!PROG_NAMES[@]}"; do
            local prog_name="${PROG_NAMES[$i]}"
            local prog_clean=$(echo "$prog_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')

            local score=0
            if [ "$base_name_clean" = "$prog_clean" ]; then
                score=100
            elif [[ "$base_name_clean" == *"$prog_clean"* ]] && [ ${#prog_clean} -ge 4 ]; then
                score=80
            elif [[ "$prog_clean" == *"$base_name_clean"* ]] && [ ${#base_name_clean} -ge 4 ]; then
                score=75
            fi

            local base_lower=$(echo "$base_name" | tr '[:upper:]' '[:lower:]')
            local prog_lower=$(echo "$prog_name" | tr '[:upper:]' '[:lower:]')
            local common_apps="audacity duckstation inkscape krita gimp blender olive lmms stacer synfig tinymediamanager ventoy balenaetcher godot friction brasero subtitleedit darktable freecad mypaint pixelorama openshot shotcut handbrake"
            for app in $common_apps; do
                if [[ "$base_lower" == *"$app"* ]] && [[ "$prog_lower" == *"$app"* ]]; then
                    score=95
                    break
                fi
            done

            if [ $score -gt $best_match_score ]; then
                best_match_score=$score
                list_url="${PROG_URLS[$i]}"
                list_source="${PROG_SOURCES[$i]}"
                list_format="${PROG_FORMATS[$i]}"
                list_hint="${PROG_HINTS[$i]}"
                found=1
            fi
        done

        if [ $found -eq 0 ] || [ $best_match_score -lt 60 ]; then
            msg "  ⊘ $base_name - not in program list" "$YELLOW"
            continue
        fi

        local latest_version=$(get_latest_version_from_url "$list_url" "$base_name" "$list_source")

        display_version_info "$base_name" "$current_version" "$latest_version"

        if [ "$current_version" = "?" ] || [ "$current_version" = "Unknown" ]; then
            if [ -n "$latest_version" ] && [ "$latest_version" != "?" ]; then
                updates+=("$df")
                update_names+=("$base_name")
                update_current+=("?")
                update_latest+=("$latest_version")
                update_urls+=("$list_url")
                update_sources+=("$list_source")
                update_formats+=("$list_format")
                update_hints+=("$list_hint")
            else
                unknown=$((unknown + 1))
            fi
        elif [ -z "$latest_version" ] || [ "$latest_version" = "?" ]; then
            unknown=$((unknown + 1))
        elif [ "$current_version" = "$latest_version" ]; then
            up_to_date=$((up_to_date + 1))
        elif version_is_newer "$latest_version" "$current_version"; then
            updates+=("$df")
            update_names+=("$base_name")
            update_current+=("$current_version")
            update_latest+=("$latest_version")
            update_urls+=("$list_url")
            update_sources+=("$list_source")
            update_formats+=("$list_format")
            update_hints+=("$list_hint")
        else
            up_to_date=$((up_to_date + 1))
        fi
    done

    echo ""

    if [ ${#updates[@]} -eq 0 ] && [ $unknown -eq 0 ]; then
        msg "  ✅ All apps up to date! ($up_to_date checked)" "$GREEN"
        pause
        return
    fi

    if [ ${#updates[@]} -gt 0 ]; then
        msg "  Updates available:" "$YELLOW"
        echo ""
        for i in "${!updates[@]}"; do
            local curr="${update_current[$i]}"
            local latest="${update_latest[$i]}"
            if [ "$curr" = "?" ]; then
                echo -e "  $((i+1)). ${update_names[$i]}: ${YELLOW}?${NC} → ${GREEN}${latest}${NC}"
            else
                echo -e "  $((i+1)). ${update_names[$i]}: ${YELLOW}${curr}${NC} → ${GREEN}${latest}${NC}"
            fi
        done
        echo ""
    fi

    [ ${#updates[@]} -gt 0 ] && msg "  ⚠️  ${#updates[@]} update(s) available" "$YELLOW"
    [ $up_to_date -gt 0 ] && msg "  ✓ $up_to_date up to date" "$GREEN"
    [ $unknown -gt 0 ] && msg "  ❓ $unknown could not be checked" "$YELLOW"

    echo ""

    if [ ${#updates[@]} -eq 0 ]; then
        pause
        return
    fi

    echo "  1. Download and install all"
    echo "  2. Select which to update"
    echo "  0. Back"
    printf "  Select: "
    IFS= read -r c
    c=$(echo "$c" | tr -d '\r' | xargs)

    case $c in
        0) return ;;
        1) download_and_install_updates ;;
        2) select_updates_to_install ;;
        *) return ;;
    esac
}

# ==============================================================================
# DOWNLOAD AND INSTALL ALL UPDATES
# Uses the SAME logic as download_new_apps for consistency
# ==============================================================================
download_and_install_updates() {
    clear
    msg "===== DOWNLOADING ${#updates[@]} UPDATE(S) =====" "$CYAN"
    echo ""

    # Build "available_" arrays from updates_ arrays
    # This makes it compatible with the same download/install flow as download_new_apps

    local available=()
    local available_names=()
    local available_urls=()
    local available_sources=()
    local available_cats=()
    local available_status=()
    local available_formats=()
    local available_descriptions=()
    local available_hints=()
    local available_versions=()
    local available_old_desktops=()
    local available_old_paths=()

    for i in "${!updates[@]}"; do
        local old_df="${updates[$i]}"
        local name="${update_names[$i]}"
        local url="${update_urls[$i]}"
        local source="${update_sources[$i]}"
        local format="${update_formats[$i]}"
        local hint="${update_hints[$i]}"
        local latest="${update_latest[$i]}"

        # Find the program list entry to get category and description
        local cat=""
        local desc=""
        local prog_name_for_lookup="$name"
        local name_clean=$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')
        for j in "${!PROG_NAMES[@]}"; do
            local prog_clean=$(echo "${PROG_NAMES[$j]}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')
            if [ "$name_clean" = "$prog_clean" ] || [[ "$name_clean" == *"$prog_clean"* ]] || [[ "$prog_clean" == *"$name_clean"* ]]; then
                cat="${PROG_CATEGORIES[$j]}"
                desc="${PROG_DESCRIPTIONS[$j]}"
                break
            fi
        done
        [ -z "$cat" ] && cat="Other"

        available+=("$i")
        available_names+=("$name")
        available_urls+=("$url")
        available_sources+=("$source")
        available_cats+=("$cat")
        available_status+=("installed")   # all are installed (that's why we update)
        available_formats+=("$format")
        available_descriptions+=("$desc")
        available_hints+=("$hint")
        available_versions+=("$latest")
        available_old_desktops+=("$old_df")
        local old_path=$(desktop_value "$old_df" "Path")
        available_old_paths+=("$old_path")
    done

    # ========================================================================
    # PHASE 1: DOWNLOAD ALL (same as download_new_apps)
    # ========================================================================
    clear
    msg "===== PHASE 1: DOWNLOADING ${#available[@]} UPDATE(S) =====" "$CYAN"
    echo ""

    local downloaded_files=()
    local downloaded_names=()
    local downloaded_formats=()
    local downloaded_old_desktops=()
    local downloaded_old_paths=()
    local failed_downloads=()
    local cancelled_all=0
    local count=0
    local flatpak_updates=()
    local flatpak_names=()

    for idx in "${available[@]}"; do
        [ $cancelled_all -eq 1 ] && break

        count=$((count+1))
        local name="${available_names[$idx]}"
        local url="${available_urls[$idx]}"
        local source="${available_sources[$idx]}"
        local format="${available_formats[$idx]}"
        local hint="${available_hints[$idx]}"
        local latest="${available_versions[$idx]}"
        local old_df="${available_old_desktops[$idx]}"
        local old_path="${available_old_paths[$idx]}"

        echo ""
        msg "[$count/${#available[@]}] Processing $name..." "$BLUE"
	
	        # ----- APT -----
        if [[ "$source" == "apt" ]]; then
            msg "  APT package: $url" "$BLUE"
            if dpkg -l "$url" 2>/dev/null | grep -q "^ii"; then
                msg "  ✓ Already installed via apt" "$GREEN"
                install_success=$((install_success + 1))
            else
                msg "  ⚠ Not installed via apt - skipping" "$YELLOW"
                failed_downloads+=("$name (apt)")
            fi
            continue
        fi
	
        # ----- Flatpak -----
        if [[ "$source" == "flatpak" ]]; then
            if ! command -v flatpak &>/dev/null; then
                msg "  ✗ Flatpak not installed" "$RED"
                failed_downloads+=("$name (no flatpak)")
                continue
            fi
            if flatpak list --app 2>/dev/null | grep -q "$url"; then
                flatpak_updates+=("$url")
                flatpak_names+=("$name")
                msg "  ✓ Queued for flatpak update" "$GREEN"
            else
                msg "  ⚠ Not installed via Flatpak - skipping" "$YELLOW"
                failed_downloads+=("$name (not flatpak)")
            fi
            continue
        fi

        # ----- Folder -----
        if [[ "$source" == "folder" ]]; then
            msg "  ⚠ Folder-based app - opening download page" "$YELLOW"
            command -v xdg-open &>/dev/null && xdg-open "$url" 2>/dev/null &
            failed_downloads+=("$name (manual)")
            continue
        fi

        # ----- GitHub / Direct -----
        local download_url=$(construct_download_url "$source" "$url" "$name" "$format" "$latest" "$hint")

        if [ -z "$download_url" ]; then
            msg "  ⚠ No portable Linux binary found, opening project page..." "$YELLOW"
            local project_url="$url"
            [[ "$source" == "github" ]] && project_url="https://github.com/${url}"
            command -v xdg-open &>/dev/null && xdg-open "$project_url" 2>/dev/null &
            failed_downloads+=("$name (no binary)")
            echo ""
            continue
        fi

        local filename=$(basename "$download_url" | sed 's/\?.*//')
        local dest="$DOWNLOADS_DIR/$filename"

        if [ -f "$dest" ]; then
            msg "  ⚠ File already exists: $filename" "$YELLOW"
            echo "  1. Overwrite and download again"
            echo "  2. Skip this file"
            printf "  Choose (1-2): "
            IFS= read -r overwrite_choice
            overwrite_choice=$(echo "$overwrite_choice" | tr -d '\r' | xargs)
            if [ "$overwrite_choice" != "1" ]; then
                msg "  ⤏ Skipped (file exists)" "$YELLOW"
                failed_downloads+=("$name (file exists)")
                echo ""
                continue
            fi
            rm -f "$dest"
        fi

        download_file "$download_url" "$dest" "$name"
        local dl_result=$?

        if [ $dl_result -eq 3 ]; then
            cancelled_all=1
            msg "  ✗ Cancelled by user" "$RED"
        elif [ $dl_result -eq 0 ]; then
            msg "  ✓ Downloaded successfully" "$GREEN"
            downloaded_files+=("$dest")
            downloaded_names+=("$name")
            downloaded_formats+=("$format")
            downloaded_old_desktops+=("$old_df")
            downloaded_old_paths+=("$old_path")
        elif [ $dl_result -eq 2 ]; then
            msg "  ⤏ Skipped by user" "$YELLOW"
            failed_downloads+=("$name (skipped)")
        else
            msg "  ✗ Download failed" "$RED"
            failed_downloads+=("$name (failed)")
        fi
        echo ""
    done

    # ========================================================================
    # PHASE 2: INSTALL ALL DOWNLOADED FILES
    # ========================================================================
    local install_success=0
    local install_failed=0
    local install_skipped=0

    if [ ${#downloaded_files[@]} -gt 0 ]; then
        clear
        msg "===== PHASE 2: INSTALLING ${#downloaded_files[@]} UPDATE(S) =====" "$CYAN"
        echo ""

        for i in "${!downloaded_files[@]}"; do
            local file="${downloaded_files[$i]}"
            local name="${downloaded_names[$i]}"
            local old_df="${downloaded_old_desktops[$i]}"
            local old_path="${downloaded_old_paths[$i]}"

            echo "[$((i+1))/${#downloaded_files[@]}] Installing $name..."

            # Remove old .desktop and folder BEFORE installing
            if [ -n "$old_df" ] && [ -f "$old_df" ]; then
                rm -f "$old_df"
                [ -n "$old_path" ] && [ -d "$old_path" ] && rm -rf "$old_path"
            fi

            # Call the REAL install_single from install.sh
            if declare -f install_single >/dev/null 2>&1; then
                INSTALL_COUNT=$((i+1))
                install_single "$file"
                local result=$?
                if [ $result -eq 0 ]; then
                    msg "  ✓ Updated successfully" "$GREEN"
                    install_success=$((install_success + 1))
                elif [ $result -eq 2 ] || [ $result -eq 3 ]; then
                    msg "  ⤏ Skipped by user" "$YELLOW"
                    install_skipped=$((install_skipped + 1))
                else
                    msg "  ✗ Install failed (code $result)" "$RED"
                    install_failed=$((install_failed + 1))
                fi
            else
                msg "  ✗ install_single not available" "$RED"
                install_failed=$((install_failed + 1))
            fi
            echo ""
        done
    fi

    # ========================================================================
    # PHASE 3: FLATPAK UPDATES
    # ========================================================================
    if [ ${#flatpak_updates[@]} -gt 0 ]; then
        clear
        msg "===== PHASE 3: UPDATING ${#flatpak_updates[@]} FLATPAK APP(S) =====" "$CYAN"
        echo ""

        for i in "${!flatpak_updates[@]}"; do
            local app_id="${flatpak_updates[$i]}"
            local name="${flatpak_names[$i]}"
            echo "[$((i+1))/${#flatpak_updates[@]}] $name ($app_id)"

            flatpak update -y "$app_id" 2>&1
            if [ $? -eq 0 ]; then
                msg "  ✓ Updated" "$GREEN"
                install_success=$((install_success + 1))
            else
                msg "  ✗ Flatpak update failed" "$RED"
                install_failed=$((install_failed + 1))
            fi
            echo ""
        done
    fi

    # ========================================================================
    # SUMMARY
    # ========================================================================
    update_db
    echo ""
    msg "═══════════════════════════════════════" "$CYAN"
    msg "  UPDATE SUMMARY:" "$BLUE"
    msg "    ✓ Downloaded: ${#downloaded_files[@]}" "$GREEN"
    msg "    ✗ Failed/Skipped: ${#failed_downloads[@]}" "$RED"
    [ ${#flatpak_updates[@]} -gt 0 ] && msg "    📦 Flatpak: ${#flatpak_updates[@]}" "$CYAN"

    if [ ${#downloaded_files[@]} -gt 0 ] || [ ${#flatpak_updates[@]} -gt 0 ]; then
        echo ""
        msg "  INSTALL SUMMARY:" "$BLUE"
        msg "    ✓ Installed: $install_success" "$GREEN"
        [ $install_skipped -gt 0 ] && msg "    ⤏ Skipped: $install_skipped" "$YELLOW"
        [ $install_failed -gt 0 ] && msg "    ✗ Failed: $install_failed" "$RED"
    fi

    msg "═══════════════════════════════════════" "$CYAN"
    pause
}

# ==============================================================================
# SELECT UPDATES TO INSTALL
# ==============================================================================
select_updates_to_install() {
    local selected=()
    while true; do
        clear
        msg "===== SELECT UPDATES =====" "$CYAN"
        msg "Selected: ${#selected[@]}" "$YELLOW"
        echo ""
        for i in "${!updates[@]}"; do
            local marker=""
            for s in "${selected[@]}"; do
                [ "$s" = "$i" ] && marker=" ${GREEN}[✓]${NC}" && break
            done
            echo -e "  $((i+1)). ${update_names[$i]}: ${update_current[$i]} → ${update_latest[$i]}$marker"
        done
        echo ""
        echo "  Numbers (1 3 5), 0=all, Enter=confirm, c=clear"
        printf "> "
        IFS= read -r input
        input=$(echo "$input" | tr -d '\r' | xargs)

        [ -z "$input" ] && break
        [ "$input" = "c" ] && { selected=(); continue; }
        [ "$input" = "0" ] && {
            if [ ${#selected[@]} -eq ${#updates[@]} ]; then
                selected=()
            else
                selected=()
                for i in $(seq 0 $((${#updates[@]}-1))); do
                    selected+=("$i")
                done
            fi
            continue
        }
        for num in $input; do
            if [ "$num" -ge 1 ] 2>/dev/null && [ "$num" -le ${#updates[@]} ]; then
                local idx=$((num-1))
                local found=0
                local new_sel=()
                for s in "${selected[@]}"; do
                    [ "$s" = "$idx" ] && found=1 || new_sel+=("$s")
                done
                [ $found -eq 0 ] && new_sel+=("$idx")
                selected=("${new_sel[@]}")
            fi
        done
    done

    [ ${#selected[@]} -eq 0 ] && return

    local orig_updates=("${updates[@]}")
    local orig_names=("${update_names[@]}")
    local orig_current=("${update_current[@]}")
    local orig_latest=("${update_latest[@]}")
    local orig_urls=("${update_urls[@]}")
    local orig_sources=("${update_sources[@]}")
    local orig_formats=("${update_formats[@]}")
    local orig_hints=("${update_hints[@]}")

    updates=()
    update_names=()
    update_current=()
    update_latest=()
    update_urls=()
    update_sources=()
    update_formats=()
    update_hints=()
    for idx in "${selected[@]}"; do
        updates+=("${orig_updates[$idx]}")
        update_names+=("${orig_names[$idx]}")
        update_current+=("${orig_current[$idx]}")
        update_latest+=("${orig_latest[$idx]}")
        update_urls+=("${orig_urls[$idx]}")
        update_sources+=("${orig_sources[$idx]}")
        update_formats+=("${orig_formats[$idx]}")
        update_hints+=("${orig_hints[$idx]}")
    done

    download_and_install_updates

    updates=("${orig_updates[@]}")
    update_names=("${orig_names[@]}")
    update_current=("${orig_current[@]}")
    update_latest=("${orig_latest[@]}")
    update_urls=("${orig_urls[@]}")
    update_sources=("${orig_sources[@]}")
    update_formats=("${orig_formats[@]}")
    update_hints=("${orig_hints[@]}")
}

# ==============================================================================
# DOWNLOAD NEW APPS
# ==============================================================================
download_new_apps() {
    clear
    msg "===== DOWNLOAD NEW APPS =====" "$CYAN"
    line
    echo ""

    display_token_status
    echo ""

    load_program_list

    if [ ${#PROG_NAMES[@]} -eq 0 ]; then
        msg "  Program list not found or empty (tried: $PROGRAM_LIST)" "$YELLOW"
        pause
        return
    fi

    local installed_bases=()
    while IFS= read -r df; do
        [ -z "$df" ] && continue
        local nm=$(desktop_value "$df" "Name")
        [ -z "$nm" ] && continue
        local base=$(get_base_name "$nm" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')
        installed_bases+=("$base")
    done < <(list_shortcuts)

    local downloaded_files_list=()
    if [ -d "$DOWNLOADS_DIR" ]; then
        for f in "$DOWNLOADS_DIR"/*; do
            [ -f "$f" ] && downloaded_files_list+=("$(basename "$f" | tr '[:upper:]' '[:lower:]')")
        done
    fi

    local available=()
    local available_names=()
    local available_urls=()
    local available_sources=()
    local available_cats=()
    local available_status=()
    local available_formats=()
    local available_descriptions=()
    local available_hints=()
    local available_versions=()

    for i in "${!PROG_NAMES[@]}"; do
        local prog_name="${PROG_NAMES[$i]}"
        local prog_base=$(get_base_name "$prog_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')
        local status=""

        for base in "${installed_bases[@]}"; do
            if [[ "$base" == "$prog_base" ]] || [[ "$base" == *"$prog_base"* ]] || [[ "$prog_base" == *"$base"* ]]; then
                status="installed"
                break
            fi
        done

        if [ -z "$status" ]; then
            for df in "${downloaded_files_list[@]}"; do
                if [[ "$df" == *"$prog_base"* ]]; then
                    status="downloaded"
                    break
                fi
            done
        fi

        available+=("$i")
        available_names+=("$prog_name")
        available_urls+=("${PROG_URLS[$i]}")
        available_sources+=("${PROG_SOURCES[$i]}")
        available_cats+=("${PROG_CATEGORIES[$i]}")
        available_status+=("$status")
        available_formats+=("${PROG_FORMATS[$i]}")
        available_descriptions+=("${PROG_DESCRIPTIONS[$i]}")
        available_hints+=("${PROG_HINTS[$i]}")

        local current_ver=""
        if [ "$status" = "installed" ]; then
            for df in $(list_shortcuts); do
                local nm=$(desktop_value "$df" "Name")
                local nm_base=$(get_base_name "$nm" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')
                if [[ "$nm_base" == "$prog_base" ]] || [[ "$nm_base" == *"$prog_base"* ]]; then
                    current_ver=$(grep -m1 '^X-AppVersion=' "$df" 2>/dev/null | cut -d= -f2-)
                    [ -z "$current_ver" ] && current_ver="?"
                    break
                fi
            done
        fi
        available_versions+=("$current_ver")
    done

    if [ ${#available[@]} -eq 0 ]; then
        msg "  ✅ No programs found in list!" "$GREEN"
        pause
        return
    fi

    local categories=()
    local cat_counts=()
    for i in "${!available_cats[@]}"; do
        local cat="${available_cats[$i]}"
        local found=0
        for idx in "${!categories[@]}"; do
            if [ "${categories[$idx]}" = "$cat" ]; then
                cat_counts[$idx]=$((cat_counts[$idx] + 1))
                found=1
                break
            fi
        done
        if [ $found -eq 0 ]; then
            categories+=("$cat")
            cat_counts+=("1")
        fi
    done

    local global_selected=()

    while true; do
        local filter_cat=""

        while true; do
            clear
            msg "===== DOWNLOAD NEW APPS =====" "$CYAN"
            line
            echo ""

            local total_installed=0
            local total_downloaded=0
            local total_available=0
            for st in "${available_status[@]}"; do
                [ "$st" = "installed" ] && total_installed=$((total_installed + 1))
                [ "$st" = "downloaded" ] && total_downloaded=$((total_downloaded + 1))
                [ -z "$st" ] && total_available=$((total_available + 1))
            done

            msg "  📦 ${#available[@]} total programs" "$BLUE"
            msg "     ✓ ${total_installed} installed  |  ⬇ ${total_downloaded} downloaded  |  📥 ${total_available} available" "$CYAN"
            echo ""

            local selected_per_category=()
            for i in "${!categories[@]}"; do
                selected_per_category[$i]=0
            done
            for idx in "${global_selected[@]}"; do
                local cat="${available_cats[$idx]}"
                for i in "${!categories[@]}"; do
                    if [ "${categories[$i]}" = "$cat" ]; then
                        selected_per_category[$i]=$((selected_per_category[$i] + 1))
                        break
                    fi
                done
            done

            echo "  Filter by category:"
            echo "  0. All categories (or press Enter to start download)"
            for i in "${!categories[@]}"; do
                local selected_text=""
                if [ ${selected_per_category[$i]} -gt 0 ]; then
                    selected_text=" ${GREEN}[${selected_per_category[$i]} selected]${NC}"
                fi
                echo -e "  $((i+1)). ${categories[$i]} (${cat_counts[$i]} apps)$selected_text"
            done
            echo ""
            if [ ${#global_selected[@]} -gt 0 ]; then
                msg "  ✓ Total selected: ${#global_selected[@]} app(s)" "$GREEN"
                local selected_names_list=""
                local max_display=8
                local count_display=0
                for idx in "${global_selected[@]}"; do
                    count_display=$((count_display + 1))
                    if [ $count_display -le $max_display ]; then
                        if [ -n "$selected_names_list" ]; then
                            selected_names_list="${selected_names_list}, "
                        fi
                        selected_names_list="${selected_names_list}${available_names[$idx]}"
                    fi
                done
                if [ ${#global_selected[@]} -gt $max_display ]; then
                    selected_names_list="${selected_names_list}, ..."
                fi
                echo "     ↳ ${selected_names_list}"
            fi
            echo ""
            msg "  ↳ Enter (empty) = Start download (if any selected)" "$GREEN"
            msg "  ↳ 0 = Show all apps (or choose a category to filter)" "$YELLOW"
            line
            printf "  Select category (0-${#categories[@]}, or Enter to download): "
            IFS= read -r cat_choice
            cat_choice=$(echo "$cat_choice" | tr -d '\r' | xargs)

            if [ -z "$cat_choice" ]; then
                if [ ${#global_selected[@]} -gt 0 ]; then
                    break 2
                else
                    return 0
                fi
            fi

            if [ "$cat_choice" = "0" ]; then
                filter_cat=""
                break
            elif [ "$cat_choice" -ge 1 ] 2>/dev/null && [ "$cat_choice" -le ${#categories[@]} ]; then
                local cidx=$((cat_choice-1))
                filter_cat="${categories[$cidx]}"
                break
            else
                msg "  Invalid choice, try again" "$RED"
                sleep 1
                continue
            fi
        done

        local selected=()
        for s in "${global_selected[@]}"; do
            if [ "${available_cats[$s]}" = "$filter_cat" ] || [ -z "$filter_cat" ]; then
                selected+=("$s")
            fi
        done

        while true; do
            clear
            msg "===== SELECT APPS TO DOWNLOAD =====" "$CYAN"
            msg "Selected in this category: ${#selected[@]} | Total selected: ${#global_selected[@]}" "$YELLOW"
            echo ""
            if [ -n "$filter_cat" ]; then
                msg "  Filter: $filter_cat" "$BLUE"
                echo ""
            fi

            local display_idx=0
            local display_map=()
            for i in "${!available[@]}"; do
                local cat="${available_cats[$i]}"
                if [ -n "$filter_cat" ]; then
                    [ "$cat" != "$filter_cat" ] && continue
                fi

                display_idx=$((display_idx+1))
                display_map+=("$i")
                local marker=""
                for s in "${selected[@]}"; do
                    [ "$s" = "$i" ] && marker=" ${GREEN}[✓]${NC}" && break
                done

                local status="${available_status[$i]}"
                local status_tag=""
                if [ "$status" = "installed" ]; then
                    status_tag=" ${GREEN}[Installed${available_versions[$i]:+ ${available_versions[$i]}}]${NC}"
                elif [ "$status" = "downloaded" ]; then
                    status_tag=" ${BLUE}[Downloaded]${NC}"
                else
                    status_tag=" ${YELLOW}[Available]${NC}"
                fi

                local desc="${available_descriptions[$i]}"
                echo -e "  ${display_idx}. ${available_names[$i]} [${cat}] ${desc:+ - $desc}$marker$status_tag"
            done

            echo ""
            echo "  Commands: Numbers (1 3 5), 0=all, Enter=confirm, c=clear, d=delete last"
            echo "  M. Main Menu"
            line
            printf "> "
            IFS= read -r input
            input=$(echo "$input" | tr -d '\r' | xargs)

            [ "$input" = "M" ] || [ "$input" = "m" ] && return 0

            if [ -z "$input" ]; then
                local new_global=()
                for g in "${global_selected[@]}"; do
                    if [ "${available_cats[$g]}" != "$filter_cat" ] && [ -n "$filter_cat" ]; then
                        new_global+=("$g")
                    fi
                done
                for s in "${selected[@]}"; do
                    new_global+=("$s")
                done
                global_selected=()
                for g in "${new_global[@]}"; do
                    local already=0
                    for check in "${global_selected[@]}"; do
                        [ "$check" = "$g" ] && already=1 && break
                    done
                    [ $already -eq 0 ] && global_selected+=("$g")
                done
                break
            fi

            [ "$input" = "c" ] && { selected=(); continue; }
            [ "$input" = "d" ] && { unset 'selected[${#selected[@]}-1]'; selected=("${selected[@]}"); continue; }
            [ "$input" = "0" ] && {
                if [ ${#selected[@]} -eq ${#display_map[@]} ]; then
                    selected=()
                else
                    selected=()
                    for i in "${!display_map[@]}"; do
                        selected+=("${display_map[$i]}")
                    done
                fi
                continue
            }
            for num in $input; do
                if [ "$num" -ge 1 ] 2>/dev/null && [ "$num" -le ${#display_map[@]} ]; then
                    local real_idx="${display_map[$((num-1))]}"
                    local found=0
                    local new_sel=()
                    for s in "${selected[@]}"; do
                        [ "$s" = "$real_idx" ] && found=1 || new_sel+=("$s")
                    done
                    [ $found -eq 0 ] && new_sel+=("$real_idx")
                    selected=("${new_sel[@]}")
                fi
            done
        done
    done

    if [ ${#global_selected[@]} -eq 0 ]; then
        return
    fi

    local DOWNLOAD_MODE=""
    while true; do
        clear
        msg "===== DOWNLOAD OPTIONS =====" "$CYAN"
        line
        echo ""
        msg "  Selected ${#global_selected[@]} app(s)" "$BLUE"
        echo ""

        local sel_installed=0
        local sel_downloaded=0
        local sel_available=0
        for idx in "${global_selected[@]}"; do
            case "${available_status[$idx]}" in
                "installed") sel_installed=$((sel_installed + 1)) ;;
                "downloaded") sel_downloaded=$((sel_downloaded + 1)) ;;
                *) sel_available=$((sel_available + 1)) ;;
            esac
        done

        echo "  ┌─────────────────────────────────────┐"
        echo "  │  📥 Available: $sel_available"
        echo "  │  ⬇ Downloaded: $sel_downloaded"
        echo "  │  ✓ Installed: $sel_installed"
        echo "  └─────────────────────────────────────┘"
        echo ""
        echo "  1. Download & Install (download all, THEN install all)"
        echo "  2. Download only (save to downloads folder, install later)"
        echo "  0. Cancel"
        echo "  M. Main Menu"
        line
        printf "Choose (1-2, 0=Cancel, M=Main Menu): "
        IFS= read -r mode_choice
        mode_choice=$(echo "$mode_choice" | tr -d '\r' | xargs)

        if [ -z "$mode_choice" ]; then
            msg "  Cancelled" "$YELLOW"
            sleep 1
            DOWNLOAD_MODE=""
            break
        fi
        if [ "$mode_choice" = "M" ] || [ "$mode_choice" = "m" ]; then
            return 0
        fi
        case $mode_choice in
            0) msg "  Cancelled" "$YELLOW"; sleep 1; DOWNLOAD_MODE=""; break ;;
            1) DOWNLOAD_MODE="install"; break ;;
            2) DOWNLOAD_MODE="download_only"; break ;;
            *) msg "  Invalid choice" "$RED"; sleep 1; continue ;;
        esac
    done

    if [ -z "$DOWNLOAD_MODE" ]; then
        return
    fi

    clear
    msg "===== PHASE 1: DOWNLOADING ${#global_selected[@]} APP(S) =====" "$CYAN"
    echo ""

    local downloaded_files=()
    local downloaded_names=()
    local failed_downloads=()
    local cancelled_all=0
    local count=0
    local skipped_installed=0
    local reinstall_installed=0

    for idx in "${global_selected[@]}"; do
        [ $cancelled_all -eq 1 ] && break

        local status="${available_status[$idx]}"
        local name="${available_names[$idx]}"

        if [ "$status" = "installed" ]; then
            echo ""
            msg "═══════════════════════════════════════" "$CYAN"
            msg "  📦 $name ${GREEN}[INSTALLED]${NC}" "$BLUE"
            msg "═══════════════════════════════════════" "$CYAN"
            msg "  This app is already installed." "$YELLOW"
            echo ""
            echo "  1. Yes - Download anyway (reinstall/update)"
            echo "  2. No  - Skip this app"
            echo "  0. Cancel all remaining downloads"
            line
            printf "  Choose (1-2, 0=Cancel): "
            IFS= read -r reinstall_choice
            reinstall_choice=$(echo "$reinstall_choice" | tr -d '\r' | xargs)

            case "$reinstall_choice" in
                0)
                    msg "  ✗ Cancelled ALL remaining" "$RED"
                    cancelled_all=1
                    continue
                    ;;
                2|"")
                    msg "  ⤏ Skipped (already installed)" "$YELLOW"
                    skipped_installed=$((skipped_installed + 1))
                    echo ""
                    continue
                    ;;
                1)
                    msg "  ✓ Reinstall/Update confirmed" "$GREEN"
                    reinstall_installed=$((reinstall_installed + 1))
                    ;;
                *)
                    msg "  ⤏ Invalid choice, skipping..." "$YELLOW"
                    skipped_installed=$((skipped_installed + 1))
                    echo ""
                    continue
                    ;;
            esac
        fi

        count=$((count+1))
        local url="${available_urls[$idx]}"
        local source="${available_sources[$idx]}"
        local format="${available_formats[$idx]}"
        local hint="${available_hints[$idx]}"
	
	echo ""
        msg "[$count/${#global_selected[@]}] Processing $name..." "$BLUE"

               # ----- APT -----
        if [[ "$source" == "apt" ]]; then
            if ! command -v apt-get &>/dev/null; then
                msg "  ✗ APT not available" "$RED"
                failed_downloads+=("$name (no apt)")
                continue
            fi

            # Use install_apt for consistency
            if install_apt "$url" "$name"; then
                downloaded_files+=("apt:$url")
                downloaded_names+=("$name")
            else
                failed_downloads+=("$name (apt failed)")
            fi
            continue
        fi
	
        echo ""
        msg "[$count/${#global_selected[@]}] Processing $name..." "$BLUE"

        # ----- Flatpak -----
        if [[ "$source" == "flatpak" ]]; then
            if ! command -v flatpak &>/dev/null; then
                msg "  ✗ Flatpak not installed" "$RED"
                failed_downloads+=("$name (no flatpak)")
                continue
            fi
            msg "  Installing $url from Flathub..." "$BLUE"
            flatpak install -y flathub "$url" 2>&1
            if [ $? -eq 0 ]; then
                msg "  ✓ Installed" "$GREEN"
                downloaded_files+=("flatpak:$url")
                downloaded_names+=("$name")
            else
                msg "  ✗ Flatpak install failed" "$RED"
                failed_downloads+=("$name (flatpak failed)")
            fi
            continue
        fi

        local latest_version=$(get_latest_version_from_url "$url" "$name" "$source")
        [ -z "$latest_version" ] && latest_version="latest"

        local download_url=$(construct_download_url "$source" "$url" "$name" "$format" "$latest_version" "$hint")

        if [ -n "$download_url" ]; then
            if [[ "$download_url" == flatpak:* ]]; then
                install_single "$download_url"
                if [ $? -eq 0 ]; then
                    downloaded_files+=("$download_url")
                    downloaded_names+=("$name")
                else
                    failed_downloads+=("$name (flatpak failed)")
                fi
                echo ""
                continue
            fi

            local filename=$(basename "$download_url" | sed 's/\?.*//')
            local dest="$DOWNLOADS_DIR/$filename"

            if [ -f "$dest" ]; then
                msg "  ⚠ File already exists: $filename" "$YELLOW"
                echo "  1. Overwrite and download again"
                echo "  2. Skip this file"
                printf "  Choose (1-2): "
                IFS= read -r overwrite_choice
                overwrite_choice=$(echo "$overwrite_choice" | tr -d '\r' | xargs)
                if [ "$overwrite_choice" != "1" ]; then
                    msg "  ⤏ Skipped (file exists)" "$YELLOW"
                    failed_downloads+=("$name (file exists)")
                    echo ""
                    continue
                fi
                rm -f "$dest"
            fi

            download_file "$download_url" "$dest" "$name"
            local dl_result=$?

            if [ $dl_result -eq 3 ]; then
                cancelled_all=1
                msg "  ✗ Cancelled by user" "$RED"
            elif [ $dl_result -eq 0 ]; then
                msg "  ✓ Downloaded successfully" "$GREEN"
                downloaded_files+=("$dest")
                downloaded_names+=("$name")
            elif [ $dl_result -eq 2 ]; then
                msg "  ⤏ Skipped by user" "$YELLOW"
                failed_downloads+=("$name (skipped)")
            else
                msg "  ✗ Download failed" "$RED"
                failed_downloads+=("$name (failed)")
            fi
        else
            msg "  ⚠ No portable Linux binary found" "$YELLOW"
            failed_downloads+=("$name (no binary found)")
        fi
        echo ""
    done

    local install_success=0
    local install_failed=0

       if [ "$DOWNLOAD_MODE" = "install" ] && [ ${#downloaded_files[@]} -gt 0 ]; then
        clear
        msg "===== PHASE 2: INSTALLING ${#downloaded_files[@]} APP(S) =====" "$CYAN"
        echo ""

        for i in "${!downloaded_files[@]}"; do
            local file="${downloaded_files[$i]}"
            local name="${downloaded_names[$i]}"
            echo "[$((i+1))/${#downloaded_files[@]}] Installing $name..."

            if [[ "$file" == apt:* ]]; then
                # APT packages are already installed in Phase 1
                msg "  ✓ Already installed via apt" "$GREEN"
                install_success=$((install_success + 1))
            elif [[ "$file" == flatpak:* ]]; then
                install_single "$file"
                if [ $? -eq 0 ]; then
                    install_success=$((install_success + 1))
                else
                    install_failed=$((install_failed + 1))
                fi
            elif [ -f "$file" ]; then
                install_single "$file"
                if [ $? -eq 0 ]; then
                    install_success=$((install_success + 1))
                else
                    install_failed=$((install_failed + 1))
                fi
            else
                msg "  ⚠ File not found: $file" "$RED"
                install_failed=$((install_failed + 1))
            fi
            echo ""
        done
    elif [ "$DOWNLOAD_MODE" = "download_only" ] && [ ${#downloaded_files[@]} -gt 0 ]; then
        msg "  Files saved to: $DOWNLOADS_DIR" "$YELLOW"
        msg "  Use 'Install (Queue)' menu to install them later" "$YELLOW"
    fi

    update_db
    echo ""
    msg "═══════════════════════════════════════" "$CYAN"
    msg "  DOWNLOAD SUMMARY:" "$BLUE"
    msg "    ✓ Downloaded: ${#downloaded_files[@]}" "$GREEN"
    msg "    ✗ Failed/Skipped: ${#failed_downloads[@]}" "$RED"
    [ $skipped_installed -gt 0 ] && msg "    ⤏ Skipped (installed): $skipped_installed" "$YELLOW"
    [ $reinstall_installed -gt 0 ] && msg "    🔄 Reinstalling: $reinstall_installed" "$CYAN"

    if [ "$DOWNLOAD_MODE" = "install" ] && [ ${#downloaded_files[@]} -gt 0 ]; then
        echo ""
        msg "  INSTALL SUMMARY:" "$BLUE"
        msg "    ✓ Installed: $install_success" "$GREEN"
        msg "    ✗ Failed: $install_failed" "$RED"
    elif [ "$DOWNLOAD_MODE" = "download_only" ] && [ ${#downloaded_files[@]} -gt 0 ]; then
        echo ""
        msg "  Files saved to: $DOWNLOADS_DIR" "$YELLOW"
        msg "  Use 'Install (Queue)' menu to install them later" "$YELLOW"
    fi

    msg "═══════════════════════════════════════" "$CYAN"
    pause
}

# ==============================================================================
# CHECK LINKS (REAL DOWNLOAD VERIFICATION - WITH VERSIONS + FULL FLATPAK SUPPORT)
# ==============================================================================
menu_check_links() {
    clear
    msg "===== CHECK LINKS (REAL DOWNLOAD VERIFICATION) =====" "$CYAN"
    line
    echo ""

    display_token_status
    echo ""

    load_program_list

    if [ ${#PROG_NAMES[@]} -eq 0 ]; then
        msg "  Program list not found or empty (tried: $PROGRAM_LIST)" "$YELLOW"
        pause
        return
    fi

    msg "  Checking ${#PROG_NAMES[@]} program links..." "$BLUE"
    echo ""

    # Ensure CACHE_DIR exists
    [ -z "$CACHE_DIR" ] && CACHE_DIR="$DATA_DIR/cache"
    mkdir -p "$CACHE_DIR"

    local success=0
    local failed=0
    local maybe=0
    local failed_names=()
    local failed_urls=()
    local failed_reasons=()
    local maybe_names=()
    local maybe_urls=()
    local maybe_reasons=()

    for i in "${!PROG_NAMES[@]}"; do
        local name="${PROG_NAMES[$i]}"
        local url="${PROG_URLS[$i]}"
        local source="${PROG_SOURCES[$i]}"
        local format="${PROG_FORMATS[$i]}"
        local hint="${PROG_HINTS[$i]}"


	        # ============================================================
        # APT
        # ============================================================
        if [[ "$source" == "apt" ]]; then
            printf "  %-30s ... " "$name"

            if ! command -v apt &>/dev/null; then
                msg "✗ APT NOT AVAILABLE" "$RED"
                failed=$((failed + 1))
                failed_names+=("$name")
                failed_reasons+=("not Debian/Ubuntu")
                continue
            fi

            if dpkg -l "$url" 2>/dev/null | grep -q "^ii"; then
                local installed_ver=$(dpkg-query -W -f='${Version}' "$url" 2>/dev/null)
                local available_ver=$(apt-cache policy "$url" 2>/dev/null | grep "Candidate:" | awk '{print $2}')
                if [ "$installed_ver" = "$available_ver" ]; then
                    msg "✓ APT v${installed_ver} (latest)" "$GREEN"
                else
                    msg "✓ APT v${installed_ver} (update: ${available_ver})" "$YELLOW"
                fi
                success=$((success + 1))
            else
                msg "✗ APT PACKAGE NOT FOUND: $url" "$RED"
                failed=$((failed + 1))
                failed_names+=("$name")
                failed_reasons+=("package not found")
            fi
            continue
        fi

        # ============================================================
        # 1. FLATPAK
        # ============================================================
        if [[ "$source" == "flatpak" ]]; then
            printf "  %-30s ... " "$name"

            # Try Flathub API v2 (appstream) first
            local version=""
            local size_mb=""
            local api_url="https://flathub.org/api/v2/appstream/${url}"
            local api_response=$(curl -s -L --max-time 15 "$api_url" 2>/dev/null)

            if [ -n "$api_response" ] && command -v jq &>/dev/null; then
                version=$(echo "$api_response" | jq -r '.releases[0].version // .version // empty' 2>/dev/null)
                # Try to get download size
                local download_size=$(echo "$api_response" | jq -r '.downloadSize // empty' 2>/dev/null)
                if [ -n "$download_size" ] && [ "$download_size" -gt 0 ] 2>/dev/null; then
                    size_mb=$((download_size / 1048576))
                fi
            fi

            # Fallback: old API v1
            if [ -z "$version" ]; then
                local alt_url="https://flathub.org/api/v1/apps/${url}"
                local alt_response=$(curl -s -L --max-time 15 "$alt_url" 2>/dev/null)
                if [ -n "$alt_response" ] && command -v jq &>/dev/null; then
                    version=$(echo "$alt_response" | jq -r '.releases[0].version // empty' 2>/dev/null)
                fi
            fi

            # Clean version
            version=$(echo "$version" | sed 's/^v//' | sed 's/-.*//' | xargs)

            if [ -n "$version" ]; then
                local size_display=""
                [ -n "$size_mb" ] && [ "$size_mb" -gt 0 ] && size_display=" (${size_mb} MB)"
                msg "✓ FLATPAK v${version}${size_display}" "$GREEN"
                success=$((success + 1))
            else
                # Try to at least confirm the app exists on Flathub
                local check_url="https://flathub.org/api/v1/apps/${url}"
                local check_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$check_url" 2>/dev/null)

                if [[ "$check_code" =~ ^(200|301|302)$ ]]; then
                    msg "✓ FLATPAK (version unknown)" "$GREEN"
                    success=$((success + 1))
                else
                    msg "✗ FLATPAK NOT FOUND" "$RED"
                    failed=$((failed + 1))
                    failed_names+=("$name")
                    failed_urls+=("flatpak:$url")
                    failed_reasons+=("not on Flathub")
                fi
            fi
            continue
        fi

        # ============================================================
        # 2. FOLDER
        # ============================================================
        if [[ "$source" == "folder" ]]; then
            printf "  %-30s ... " "$name"

            local version=$(get_latest_version_from_folder "$url" "$name")
            local page_code=$(curl -s -o /dev/null -w "%{http_code}" -L --max-time 10 "$url" 2>/dev/null)

            if [[ "$page_code" =~ ^(200|301|302|303|307|308)$ ]]; then
                if [ -n "$version" ]; then
                    msg "✓ FOLDER v${version}" "$GREEN"
                    success=$((success + 1))
                else
                    msg "⚠ FOLDER (page OK, version unknown)" "$YELLOW"
                    maybe=$((maybe + 1))
                    maybe_names+=("$name")
                    maybe_urls+=("$url")
                    maybe_reasons+=("cannot detect version")
                fi
            else
                msg "✗ FOLDER PAGE FAILED (${page_code})" "$RED"
                failed=$((failed + 1))
                failed_names+=("$name")
                failed_urls+=("$url")
                failed_reasons+=("page HTTP $page_code")
            fi
            continue
        fi

        # ============================================================
        # 3. GITHUB / DIRECT
        # ============================================================
        local version=$(get_latest_version_from_url "$url" "$name" "$source")
        [ -z "$version" ] && version="?"

        local download_url=$(construct_download_url "$source" "$url" "$name" "$format" "$version" "$hint")

        local size_display=""
        local file_type=""
        local version_display=""

        if [ -n "$download_url" ]; then
            # Determine file type from URL
            local lower_url=$(echo "$download_url" | tr '[:upper:]' '[:lower:]')
            case "$lower_url" in
                *.appimage) file_type="AppImage" ;;
                *.tar.gz|*.tgz) file_type="tar.gz" ;;
                *.tar.xz|*.txz) file_type="tar.xz" ;;
                *.tar.bz2|*.tbz2) file_type="tar.bz2" ;;
                *.zip) file_type="zip" ;;
                *.7z) file_type="7z" ;;
                *) file_type="FILE" ;;
            esac

            # Try to get file size
            local content_length=$(curl -s -I -L --max-time 8 "$download_url" 2>/dev/null | grep -i "^Content-Length:" | tail -1 | awk '{print $2}' | tr -d '\r')
            if [ -n "$content_length" ] && [ "$content_length" -gt 0 ] 2>/dev/null; then
                local size_mb=$((content_length / 1048576))
                if [ $size_mb -gt 0 ]; then
                    size_display=" (${size_mb} MB)"
                else
                    local size_kb=$((content_length / 1024))
                    [ $size_kb -gt 0 ] && size_display=" (${size_kb} KB)"
                fi
            fi
        fi

        # Version display
        if [ -n "$version" ] && [ "$version" != "?" ] && [ "$version" != "latest" ]; then
            version_display=" v${version}"
        elif [ "$version" = "?" ]; then
            version_display=" (version unknown)"
        fi

        printf "  %-30s ... " "$name"

        if [ -n "$download_url" ]; then
            # Verify URL is accessible
            local http_code=$(curl -s -o /dev/null -w "%{http_code}" -L --max-time 10 "$download_url" 2>/dev/null)

            if [[ "$http_code" =~ ^(200|206|301|302|303|307|308)$ ]]; then
                [ -z "$size_display" ] && size_display=" (size unknown)"
                msg "✓ ${file_type}${version_display}${size_display}" "$GREEN"
                success=$((success + 1))
            else
                msg "✗ ${file_type} NOT FOUND (HTTP ${http_code})${version_display}" "$RED"
                failed=$((failed + 1))
                failed_names+=("$name")
                failed_urls+=("$download_url")
                failed_reasons+=("HTTP $http_code")
            fi
        else
            # No download URL constructed - check main page
            local main_url=""
            if [[ "$source" == "github" ]]; then
                main_url="https://github.com/${url}"
            else
                main_url="$url"
            fi

            local main_code=$(curl -s -o /dev/null -w "%{http_code}" -L --max-time 10 "$main_url" 2>/dev/null)

            if [[ "$main_code" =~ ^(200|301|302|303|307|308)$ ]]; then
                local display_version=""
                [ -n "$version" ] && [ "$version" != "?" ] && [ "$version" != "latest" ] && display_version=" v${version}"
                msg "⚠ PAGE OK${display_version}, NO ${format} BINARY" "$YELLOW"
                maybe=$((maybe + 1))
                maybe_names+=("$name")
                maybe_urls+=("$main_url")
                maybe_reasons+=("no ${format} in assets")
            else
                msg "✗ PAGE FAILED (HTTP ${main_code})" "$RED"
                failed=$((failed + 1))
                failed_names+=("$name")
                failed_urls+=("${main_url}")
                failed_reasons+=("page HTTP $main_code")
            fi
        fi
    done

    # ============================================================
    # SUMMARY
    # ============================================================
    echo ""
    line
    msg "  SUMMARY:" "$BLUE"
    msg "    ✓ Working: $success" "$GREEN"
    msg "    ⚠ Page OK but no binary: $maybe" "$YELLOW"
    msg "    ✗ Broken/Failed: $failed" "$RED"

    if [ $maybe -gt 0 ]; then
        echo ""
        msg "  ⚠ Programs with page OK but no download binary:" "$YELLOW"
        for i in "${!maybe_names[@]}"; do
            echo "    - ${maybe_names[$i]}: ${maybe_reasons[$i]}"
            echo "      URL: ${maybe_urls[$i]}"
        done
    fi

    if [ $failed -gt 0 ]; then
        echo ""
        msg "  ✗ Broken/Failed links:" "$RED"
        for i in "${!failed_names[@]}"; do
            echo "    - ${failed_names[$i]}: ${failed_reasons[$i]}"
            echo "      URL: ${failed_urls[$i]}"
        done
    fi

    line
    pause
}

# ==============================================================================
# CACHE MANAGEMENT
# ==============================================================================
clear_download_cache() {
    if [ -d "$CACHE_DIR" ]; then
        rm -rf "$CACHE_DIR"/*
        mkdir -p "$CACHE_DIR"
        msg "  ✓ Download cache cleared" "$GREEN"
    fi
    pause
}

# ==============================================================================
# UPDATES MAIN MENU
# ==============================================================================
menu_updates() {
    while true; do
        clear
        msg "===== UPDATES & DOWNLOADS =====" "$CYAN"
        line
        echo ""
        msg "  ↳ Enter (empty) = Back" "$YELLOW"
        echo ""

        local token=$(get_github_token)
        if [ -n "$token" ]; then
            local rate_info=$(check_github_rate_limit)
            local remaining=$(echo "$rate_info" | grep "remaining=" | cut -d= -f2)
            local limit=$(echo "$rate_info" | grep "limit=" | cut -d= -f2)
            local reset=$(echo "$rate_info" | grep "reset=" | cut -d= -f2)
            if [ "$limit" = "0" ] || [ "$reset" = "INVALID" ]; then
                msg "  ⚠ Token invalid - anonymous mode (60 req/h)" "$YELLOW"
            else
                msg "  ✓ Token OK (rate limit: $remaining / $limit)" "$GREEN"
            fi
        else
            msg "  ℹ️  No token - anonymous mode (60 req/h)" "$BLUE"
        fi
        echo ""

        echo "  1. Check for updates (installed apps)"
        echo "  2. Download new apps (from program list)"
        echo "  3. Clear download cache"
        echo "  4. Check links (verify program URLs)"
        echo ""
        line
        printf "Choose (1-4, or press Enter to go back): "
        IFS= read -r choice
        choice=$(echo "$choice" | tr -d '\r' | xargs)

        [ -z "$choice" ] && return

        case "$choice" in
            1) menu_check_updates ;;
            2) download_new_apps ;;
            3) clear_download_cache ;;
            4) menu_check_links ;;
            *) msg "  Invalid choice" "$RED"; sleep 1 ;;
        esac
    done
}
