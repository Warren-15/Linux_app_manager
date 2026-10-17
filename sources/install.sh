# ==============================================================================
# APT INSTALLER - Install from system repositories
# ==============================================================================
install_apt() {
    local package="$1"
    local name="$2"

    # Normalize package name (remove spaces if any)
    package=$(echo "$package" | tr -d ' ')

    # Check if apt is available
    if ! command -v apt-get &>/dev/null; then
        msg "  ✗ apt not available (not Debian/Ubuntu)" "$RED"
        return 1
    fi

    # Check if package exists in repos
    if ! apt-cache show "$package" &>/dev/null; then
        msg "  ✗ Package not found in apt repos: $package" "$RED"
        return 1
    fi

    # Check if already installed
    local was_installed=0
    if dpkg -l "$package" 2>/dev/null | grep -q "^ii"; then
        local installed_ver=$(dpkg-query -W -f='${Version}' "$package" 2>/dev/null)
        msg "  ✓ $name is already installed (via apt v$installed_ver)" "$GREEN"
        was_installed=1
    else
        msg "  Installing $package via apt (this may take a while)..." "$BLUE"
        echo ""

        # Use apt-get with visible progress (no tail)
        if sudo apt-get install -y -o Dpkg::Progress-Fancy="1" -o APT::Color="1" "$package"; then
            msg "  ✓ Installed: $name" "$GREEN"
        else
            msg "  ✗ Failed to install $package" "$RED"
            msg "  Try manually: sudo apt install $package" "$YELLOW"
            return 1
        fi
    fi

    # ============================================================
    # Special handling for Geany: Download & install color schemes
    # ============================================================
    if [[ "$package" == "geany" ]]; then
        msg "  🎨 Setting up Geany color schemes..." "$BLUE"

        # Determine the real user's home directory (in case script runs with sudo)
        local target_user="${SUDO_USER:-$USER}"
        local target_home=$(getent passwd "$target_user" | cut -d: -f6)
        if [ -z "$target_home" ]; then
            target_home="$HOME"
        fi

        local geany_config_dir="$target_home/.config/geany"
        local colorschemes_dir="$geany_config_dir/colorschemes"
        local temp_themes_dir="/tmp/geany-themes-$$"

        # Create colorschemes directory if it doesn't exist
        mkdir -p "$colorschemes_dir"

        # Download and extract geany-themes (using the official repo)
        # We use git if available, otherwise fallback to downloading a tarball
        if command -v git &>/dev/null; then
            msg "    Cloning geany-themes repository..." "$BLUE"
            if git clone --depth 1 https://github.com/geany/geany-themes.git "$temp_themes_dir" &>/dev/null; then
                # Copy all .conf files from the colorschemes directory
                cp "$temp_themes_dir"/colorschemes/*.conf "$colorschemes_dir/" 2>/dev/null
                msg "    ✓ Color schemes installed to $colorschemes_dir" "$GREEN"
            else
                msg "    ✗ Failed to clone geany-themes repository" "$RED"
            fi
            rm -rf "$temp_themes_dir"
        else
            # Fallback: Download tarball directly
            msg "    git not found, downloading tarball..." "$YELLOW"
            local tarball_url="https://github.com/geany/geany-themes/archive/refs/heads/master.tar.gz"
            if curl -sL "$tarball_url" -o /tmp/geany-themes.tar.gz; then
                tar -xzf /tmp/geany-themes.tar.gz -C /tmp
                local extracted_dir=$(find /tmp -maxdepth 1 -type d -name "geany-themes-*" | head -1)
                if [ -n "$extracted_dir" ]; then
                    cp "$extracted_dir"/colorschemes/*.conf "$colorschemes_dir/" 2>/dev/null
                    msg "    ✓ Color schemes installed to $colorschemes_dir" "$GREEN"
                fi
                rm -rf /tmp/geany-themes.tar.gz "$extracted_dir"
            else
                msg "    ✗ Failed to download geany-themes" "$RED"
            fi
        fi

        # Fix ownership if running as root
        if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
            chown -R "$SUDO_USER:$SUDO_USER" "$geany_config_dir" 2>/dev/null
        fi

        msg "  ✓ Geany themes setup complete (restart Geany to see them)" "$GREEN"
    fi

    return 0
}

# ==============================================================================
# INSTALL SINGLE - with Ctrl+C cancel support
# ==============================================================================

install_single() {
    local file="$1"
    local bn="$(basename "$file")"
    local app="$(app_name_from_file "$bn")"
    local version=$(extract_version "$bn")


    # ============================================================
    # APT source
    # ============================================================
    if [[ "$file" == apt:* ]]; then
        local package="${file#apt:}"
        local app_name=$(echo "$package" | sed 's/^[^ ]* //' | sed 's/-/_/g')
        # Use the full name if present, otherwise use the package name
        local display_name=$(echo "$package" | sed 's/^\([^:]*\):.*/\1/')
        install_apt "$package" "$display_name"
        return $?
    fi

    # Clean app name
    app=$(echo "$app" | sed 's/\.Tar//' | sed 's/\.tar//' | sed 's/Linux//' | sed 's/X64//' | sed 's/x86_64//' | sed 's/  / /g' | sed 's/ $//')

    local safe="$(sanitize "$app")"
    local target="$APPLICATIONS_DIR/$safe"
    local display_name="$app"
    [ -n "$version" ] && display_name="$app $version"

    echo "[$((${INSTALL_COUNT:-0}+1))] Installing: $display_name"

    # Conflict detection
    local base_name=$(get_base_name "$display_name")
    local existing_df=$(find_existing_by_base "$base_name")
    local has_conflict=0

    if [ -n "$existing_df" ]; then
        local existing_path=$(desktop_value "$existing_df" "Path")
        local existing_safe=$(sanitize "$(desktop_value "$existing_df" "Name")")

        if [ -n "$existing_path" ] && [ -d "$existing_path" ]; then
            has_conflict=1
        elif [ -d "$APPLICATIONS_DIR/$existing_safe" ]; then
            has_conflict=1
        else
            rm -f "$existing_df"
        fi
    fi

    if [ $has_conflict -eq 1 ]; then
        local existing_name=$(desktop_value "$existing_df" "Name")
        msg "  Found existing: $existing_name" "$YELLOW"
        echo "    1. Overwrite  2. Add (keep both)  3. Skip"
        printf "  Select: "
        read c
        case $c in
            1)
                local old_path=$(desktop_value "$existing_df" "Path")
                rm -f "$existing_df"
                [ -n "$old_path" ] && [ -d "$old_path" ] && rm -rf "$old_path"
                [ -d "$APPLICATIONS_DIR/$existing_safe" ] && rm -rf "$APPLICATIONS_DIR/$existing_safe"
                msg "  Removed: $existing_name" "$YELLOW"
                ;;
            2)
                safe="${safe}_${version}"
                target="$APPLICATIONS_DIR/$safe"
                ;;
            *) msg "  Skipped" "$YELLOW"; return ;;
        esac
    fi

    if [ -d "$target" ]; then
        if [ -f "$DESKTOP_DIR/$safe.desktop" ]; then
            msg "  '$display_name' already installed" "$YELLOW"
            echo "    1. Overwrite  2. Skip"
            printf "  Select: "
            read c
            [ "$c" = "1" ] && { rm -f "$DESKTOP_DIR/$safe.desktop"; rm -rf "$target"; } || { msg "  Skipped" "$YELLOW"; return; }
        else
            msg "  Folder exists without shortcut, removing" "$YELLOW"
            rm -rf "$target"
        fi
    fi

    rm -rf "$target"
    mkdir -p "$target"

    echo "0" > /tmp/install_choice_$$
    trap '
        echo ""
        echo "  1. Cancel this install (delete folder)"
        echo "  2. Cancel ALL remaining"
        printf "  Select: "
        IFS= read -r c
        echo "$c" > /tmp/install_choice_$$
        rm -rf "'$target'" 2>/dev/null
        rm -rf "'$tmpdir'" 2>/dev/null
    ' INT

    if [[ "$bn" =~ \.(zip|7z|tar\.gz|tgz|tar\.xz|tar\.bz2|rar)$ ]]; then
        msg "  Extracting..." "$BLUE"
        local tmpdir="$TEMP_DIR/${safe}_extract"
        rm -rf "$tmpdir"
        mkdir -p "$tmpdir"

        local extract_ok=0
        if extract_archive "$file" "$tmpdir"; then
            extract_ok=1
        fi

        trap - INT
        local user_choice=$(cat /tmp/install_choice_$$ 2>/dev/null)
        rm -f /tmp/install_choice_$$

        if [ "$user_choice" = "2" ]; then
            msg "  ✗ Cancelled ALL remaining" "$RED"
            rm -rf "$target" 2>/dev/null; rm -rf "$tmpdir" 2>/dev/null
            return 3
        fi
        if [ "$user_choice" = "1" ]; then
            msg "  ⤏ Cancelled (folder deleted)" "$YELLOW"
            rm -rf "$target" 2>/dev/null; rm -rf "$tmpdir" 2>/dev/null
            return 2
        fi

        if [ $extract_ok -eq 0 ]; then
            msg "  ✗ Extract failed" "$RED"
            rm -rf "$tmpdir"
            return 1
        fi

        # ============================================================
        # SMART FLATTENING - Use unified function from utils.sh
        # ============================================================
        smart_flatten "$tmpdir" "$target"

        # Fallback: if smart_flatten left target empty, copy everything
        if [ -z "$(ls -A "$target" 2>/dev/null)" ]; then
            msg "  ⚠ Smart flatten produced empty folder, using fallback" "$YELLOW"
            shopt -s dotglob
            cp -r "$tmpdir"/* "$target/" 2>/dev/null
            shopt -u dotglob
        fi

        rm -rf "$tmpdir"
        msg "  ✓ Extracted" "$GREEN"

    elif [[ "$bn" == *.AppImage ]]; then
        cp "$file" "$target/$bn"
        chmod +x "$target/$bn"

        trap - INT
        local user_choice=$(cat /tmp/install_choice_$$ 2>/dev/null)
        rm -f /tmp/install_choice_$$

        if [ "$user_choice" = "2" ]; then
            msg "  ✗ Cancelled ALL remaining" "$RED"
            rm -rf "$target" 2>/dev/null
            return 3
        fi
        if [ "$user_choice" = "1" ]; then
            msg "  ⤏ Cancelled (folder deleted)" "$YELLOW"
            rm -rf "$target" 2>/dev/null
            return 2
        fi

        msg "  ✓ Copied AppImage" "$GREEN"
    else
        cp "$file" "$target/"
        chmod +x "$target/$bn" 2>/dev/null

        trap - INT
        local user_choice=$(cat /tmp/install_choice_$$ 2>/dev/null)
        rm -f /tmp/install_choice_$$

        if [ "$user_choice" = "2" ]; then
            msg "  ✗ Cancelled ALL remaining" "$RED"
            rm -rf "$target" 2>/dev/null
            return 3
        fi
        if [ "$user_choice" = "1" ]; then
            msg "  ⤏ Cancelled (folder deleted)" "$YELLOW"
            rm -rf "$target" 2>/dev/null
            return 2
        fi

        msg "  ✓ Copied" "$GREEN"
    fi

    trap - INT

    local user_choice=$(cat /tmp/install_choice_$$ 2>/dev/null)
    rm -f /tmp/install_choice_$$

    if [ "$user_choice" = "2" ]; then
        msg "  ✗ Cancelled ALL remaining" "$RED"
        rm -rf "$target" 2>/dev/null
        return 3
    fi
    if [ "$user_choice" = "1" ]; then
        msg "  ⤏ Cancelled (folder deleted)" "$YELLOW"
        rm -rf "$target" 2>/dev/null
        return 2
    fi

    chmod -R 755 "$target"

    local exe="$(find_executable "$target")"
    if [ -z "$exe" ]; then
        msg "  ✗ No executable found in:" "$RED"
        msg "    $target" "$RED"
        echo ""
        msg "  Contents:" "$YELLOW"
        find "$target" -maxdepth 3 -type f | head -20
        return
    fi
    msg "  Exec: $(basename "$exe")" "$BLUE"

    local icon=""
    local matched_icon=$(find_matching_icon_smart "$app" "$SCRIPT_DIR")

    if [ -n "$matched_icon" ]; then
        cp "$matched_icon" "$target/$(basename "$matched_icon")"
        icon="$target/$(basename "$matched_icon")"
        msg "  Icon: $(basename "$matched_icon") (matched)" "$BLUE"
    else
        select_icon "$target" "$display_name" "install"
        icon="$ICON_RESULT"
        if [ -n "$icon" ] && [[ "$icon" == "$SCRIPT_DIR/"* ]]; then
            cp "$icon" "$target/$(basename "$icon")"
            icon="$target/$(basename "$icon")"
        fi
    fi

    load_program_list
    local cat=$(lookup_category "$app")
    local comment=$(lookup_comment "$app")

    if [ -z "$cat" ]; then
        cat="Other"
        msg "  Category: Other (not in list)" "$YELLOW"
    else
        msg "  Category: $cat" "$BLUE"
    fi
    [ -n "$comment" ] && msg "  Description: $comment" "$BLUE"

    # Store version in .desktop
    local stored_version=$(extract_version "$bn")
    [ -z "$stored_version" ] && stored_version=$(extract_version_from_name "$display_name")
    [ -z "$stored_version" ] && stored_version="Unknown"

    create_desktop_full "$display_name" "$exe" "$icon" "$cat" "$target" "$comment" "$stored_version"
    msg "  ✓ Installed successfully (runs as root)" "$GREEN"
    return 0
}
# ==============================================================================
# INSTALL MENU (Queue)
# ==============================================================================
menu_install() {
    cleanup_empty_files
    load_program_list

    local files=()
    for f in "$DOWNLOADS_DIR"/*; do
        [ -f "$f" ] || continue
        is_installable_file "$f" && files+=("$f")
    done

    if [ ${#files[@]} -eq 0 ]; then
        msg "No installable files found" "$YELLOW"
        pause
        return
    fi

    IFS=$'\n' files=($(sort -f <<<"${files[*]}"))
    unset IFS

    local selected=()
    while true; do
        clear
        msg "===== INSTALL (Queue) =====" "$CYAN"
        msg "Selected: ${#selected[@]} item(s)" "$YELLOW"
        echo ""
        msg "  ↳ Enter (empty) = Confirm & Install" "$YELLOW"
        echo ""

        for i in "${!files[@]}"; do
            local app_name=$(app_name_from_file "${files[$i]}")
            local safe_name=$(sanitize "$app_name")
            local filename=$(basename "${files[$i]}")

            local size=$(stat -c %s "${files[$i]}" 2>/dev/null || stat -f %z "${files[$i]}" 2>/dev/null)
            local size_display=""
            if [ -n "$size" ]; then
                if [ $size -gt 1048576 ]; then
                    size_display=" ($((size / 1048576)) MB)"
                elif [ $size -gt 1024 ]; then
                    size_display=" ($((size / 1024)) KB)"
                fi
            fi

            local installed_flag=""
            if is_app_installed "$safe_name"; then
                installed_flag="${RED}[installed]${NC}"
            fi

            local selected_flag=""
            for s in "${selected[@]}"; do
                [ "$s" = "$i" ] && selected_flag="${GREEN}[✓]${NC}"
            done

            echo -e "  $((i+1)). $app_name${size_display} → $filename $installed_flag $selected_flag"
        done

        echo ""
        echo "  M. Main Menu"
        echo ""
        echo "  Commands: Numbers (1 3 5), 0=all, c=clear"
        line
        echo ""
        printf "> "

        read input

        if [ -z "$input" ]; then
            [ ${#selected[@]} -gt 0 ] && break || return
        fi

        [ "$input" = "M" ] || [ "$input" = "m" ] && return 0
        [ "$input" = "c" ] && { selected=(); continue; }

        [ "$input" = "0" ] && {
            if [ ${#selected[@]} -eq ${#files[@]} ]; then
                selected=()
            else
                selected=()
                for i in "${!files[@]}"; do selected+=("$i"); done
            fi
            continue
        }

        for num in $input; do
            if [ "$num" -ge 1 ] 2>/dev/null && [ "$num" -le ${#files[@]} ]; then
                local idx=$((num-1)) found=0 new_sel=()
                for s in "${selected[@]}"; do [ "$s" = "$idx" ] && found=1 || new_sel+=("$s"); done
                [ $found -eq 0 ] && new_sel+=("$idx")
                selected=("${new_sel[@]}")
            fi
        done
    done

    clear
    msg "===== INSTALLING ${#selected[@]} APP(S) =====" "$CYAN"
    echo ""

    local count=0
    local cancelled=0
    local installed=0
    local failed=0

    for idx in "${selected[@]}"; do
        count=$((count+1))
        INSTALL_COUNT=$count

        local file="${files[$idx]}"
        local app_name=$(app_name_from_file "$file")
        echo "[$count/${#selected[@]}] Installing: $app_name"

        install_single "$file"
        local result=$?

        if [ $result -eq 3 ]; then
            cancelled=1
            break
        elif [ $result -eq 0 ]; then
            installed=$((installed + 1))
        else
            failed=$((failed + 1))
        fi
        echo ""
    done

    update_db
    echo ""
    msg "═══════════════════════════════════════" "$CYAN"
    if [ $cancelled -eq 1 ]; then
        msg "  ⚠️ Aborted by user" "$YELLOW"
        msg "    ✓ Installed: $installed" "$GREEN"
        msg "    ✗ Failed: $failed" "$RED"
    else
        msg "  ✅ Done!" "$GREEN"
        msg "    ✓ Installed: $installed" "$GREEN"
        msg "    ✗ Failed: $failed" "$RED"
    fi
    msg "═══════════════════════════════════════" "$CYAN"
    pause
}

# ------------------------------------------------------------------------------
# CREATE SHORTCUT MAIN MENU
# ------------------------------------------------------------------------------

menu_create_shortcut() {
    while true; do
        clear
        msg "===== CREATE SHORTCUT =====" "$CYAN"
        line
        echo ""
        msg "  ↳ Enter (empty) = Back" "$YELLOW"
        echo ""
        echo "  1. From installed apps (in /Applications)"
        echo "  2. From other folder (enter custom path)"
        echo ""
        echo "  M. Main Menu"
        line
        echo ""
        printf "Choose (1-2, M, or press Enter): "

        read input
        [ -z "$input" ] && return
        [ "$input" = "M" ] || [ "$input" = "m" ] && return 0

        case "$input" in
            1) shortcut_from_applications ;;
            2) shortcut_from_custom_path ;;
            *) msg "  Invalid choice (1-2, M, or Enter)" "$RED"; sleep 1 ;;
        esac
    done
}

shortcut_from_custom_path() {
    clear
    msg "===== SHORTCUT (Custom Path) =====" "$CYAN"
    line
    echo ""
    msg "  ↳ Enter (empty) = Back" "$YELLOW"
    echo ""
    printf "  Enter folder path containing the program: "
    read custom_path

    [ -z "$custom_path" ] && return

    if [ ! -d "$custom_path" ]; then
        msg "  Directory not found: $custom_path" "$RED"
        pause
        return
    fi

    local exe="$(find_executable "$custom_path")"
    if [ -z "$exe" ]; then
        msg "  No executable found in: $custom_path" "$RED"
        msg "  Make sure the folder contains an executable file" "$YELLOW"
        pause
        return
    fi

    msg "  Found executable: $(basename "$exe")" "$GREEN"

    local name="$(app_name_from_file "$exe")"
    local safe="$(sanitize "$name")"

    if [ -f "$DESKTOP_DIR/$safe.desktop" ]; then
        msg "Shortcut already exists!" "$YELLOW"
        sleep 1
        edit_shortcut "$DESKTOP_DIR/$safe.desktop"
        return
    fi

    printf "  Name (Enter='$name'): "
    read x
    [ -n "$x" ] && name="$x"

    select_icon "$custom_path" "$name"
    local icon="$ICON_RESULT"

    select_category || CATEGORY_RESULT="Other"
    local cat="$CATEGORY_RESULT"

    msg "  Selected category: $cat" "$BLUE"

    create_desktop "$name" "$exe" "$icon" "$cat" "$custom_path"
    update_db
    msg "✓ Shortcut created (runs as root): $name" "$GREEN"
    pause
}

shortcut_from_applications() {
    clear
    msg "===== SHORTCUT (Applications) =====" "$CYAN"
    line
    echo ""
    msg "  ↳ Enter (empty) = Back" "$YELLOW"
    echo ""

    local dirs=()
    for d in "$APPLICATIONS_DIR"/*/; do
        [ -d "$d" ] && dirs+=("$(basename "$d")")
    done

    [ "${#dirs[@]}" -eq 0 ] && { msg "No applications found" "$YELLOW"; pause; return; }

    local i
    for i in "${!dirs[@]}"; do
        local disp=$(echo "${dirs[$i]}" | sed 's/_/ /g')
        if [ -f "$DESKTOP_DIR/${dirs[$i]}.desktop" ]; then
            echo -e "  $((i+1)). $disp ${GREEN}[✓]${NC}"
        else
            echo "  $((i+1)). $disp [✗]"
        fi
    done
    echo ""
    echo "  M. Main Menu"
    line
    printf "Select app (1-${#dirs[@]}, M, or press Enter): "
    read c

    [ -z "$c" ] && return
    [ "$c" = "M" ] || [ "$c" = "m" ] && return 0
    [ "$c" -lt 1 ] 2>/dev/null && return
    [ "$c" -gt ${#dirs[@]} ] 2>/dev/null && return

    local folder="${dirs[$((c-1))]}"
    local path="$APPLICATIONS_DIR/$folder"
    local disp=$(echo "$folder" | sed 's/_/ /g')

    if [ -f "$DESKTOP_DIR/$folder.desktop" ]; then
        msg "Shortcut already exists!" "$YELLOW"
        sleep 1
        edit_shortcut "$DESKTOP_DIR/$folder.desktop"
        return
    fi

    local exe="$(find_executable "$path")"
    [ -z "$exe" ] && { msg "No executable found" "$RED"; pause; return; }

    printf "Name (Enter='$disp'): "
    read name
    [ -z "$name" ] && name="$disp"

    select_icon "$path" "$name"
    local icon="$ICON_RESULT"
    [ -n "$icon" ] && [[ "$icon" == "$SCRIPT_DIR/"* ]] && {
        cp "$icon" "$path/$(basename "$icon")"
        icon="$path/$(basename "$icon")"
    }

    select_category || CATEGORY_RESULT="Other"
    local cat="$CATEGORY_RESULT"

    msg "  Selected category: $cat" "$BLUE"

    create_desktop "$name" "$exe" "$icon" "$cat" "$path"
    update_db
    msg "✓ Shortcut created (runs as root): $name" "$GREEN"
    pause
}
