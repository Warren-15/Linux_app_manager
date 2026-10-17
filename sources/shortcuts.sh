# ------------------------------------------------------------------------------
# Ensure category is XDG-compliant for .desktop files
# ------------------------------------------------------------------------------
xdg_safe_category() {
    local cat="$1"
    case "$cat" in
        Utility|Game|Graphics|Network|Office|AudioVideo|Development|System|Education|Science|Settings)
            echo "$cat" ;;
        "Accessories")   echo "Utility" ;;
        "Games")         echo "Game" ;;
        "Graphics")      echo "Graphics" ;;
        "Internet")      echo "Network" ;;
        "Office")        echo "Office" ;;
        "Sound & Video") echo "AudioVideo" ;;
        "Programming")   echo "Development" ;;
        "System")        echo "System" ;;
        "Other")         echo "Other" ;;
        *)               echo "$(echo "$cat" | tr -cd '[:alnum:]')" ;;
    esac
}

# ------------------------------------------------------------------------------
# SHORTCUTS - All run as root
# ------------------------------------------------------------------------------

create_desktop() {
    local name="$1" exec="$2" icon="$3" cat="$4" path="$5"
    local safe="$(sanitize "$name")"
    local file="$DESKTOP_DIR/$safe.desktop"
    local xdg_cat=$(xdg_safe_category "$cat")
    local root_prefix=$(get_root_prefix)
    
    # Build Exec with root prefix
    local full_exec
    if [ -n "$root_prefix" ]; then
        full_exec="$root_prefix $exec"
    else
        full_exec="$exec"
    fi

    cat > "$file" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$name
Comment=$name
Exec=$full_exec
Path=$path
Icon=$icon
Terminal=false
Categories=$xdg_cat
StartupNotify=true
EOF

    chmod 755 "$file"
    [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ] && chown "$REAL_USER:$REAL_USER" "$file"
}

create_desktop_with_comment() {
    local name="$1" exec="$2" icon="$3" cat="$4" path="$5" comment="$6"
    local safe="$(sanitize "$name")"
    local file="$DESKTOP_DIR/$safe.desktop"
    local xdg_cat=$(xdg_safe_category "$cat")
    local root_prefix=$(get_root_prefix)

    [ -z "$comment" ] && comment="$name"
    if [ -z "$icon" ] || [ ! -f "$icon" ]; then
        icon="applications-default"
    fi

    local full_exec
    if [ -n "$root_prefix" ]; then
        full_exec="$root_prefix $exec"
    else
        full_exec="$exec"
    fi

    cat > "$file" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$name
Comment=$comment
Exec=$full_exec
Path=$path
Icon=$icon
Terminal=false
Categories=$xdg_cat;
StartupNotify=true
EOF

    chmod 755 "$file"
    [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ] && chown "$REAL_USER:$REAL_USER" "$file"
}

create_desktop_full() {
    local name="$1" exec="$2" icon="$3" cat="$4" path="$5" comment="$6" version="$7"
    local safe="$(sanitize "$name")"
    local file="$DESKTOP_DIR/$safe.desktop"
    local xdg_cat=$(xdg_safe_category "$cat")
    local root_prefix=$(get_root_prefix)

    [ -z "$comment" ] && comment="$name"
    [ -z "$version" ] && version="Unknown"

    local full_exec
    if [ -n "$root_prefix" ]; then
        full_exec="$root_prefix $exec"
    else
        full_exec="$exec"
    fi

    cat > "$file" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$name
Comment=$comment
Exec=$full_exec
Path=$path
Icon=$icon
Terminal=false
Categories=$xdg_cat;
StartupNotify=true
X-AppVersion=$version
EOF

    chmod 755 "$file"
    [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ] && chown "$SUDO_USER:$SUDO_USER" "$file"
}

create_desktop_with_version() {
    create_desktop_full "$@"
}

update_db() {
    update-desktop-database "$DESKTOP_DIR" 2>/dev/null
    command -v xdg-desktop-menu &>/dev/null && xdg-desktop-menu forceupdate 2>/dev/null
    command -v kbuildsycoca5 &>/dev/null && kbuildsycoca5 2>/dev/null
}

list_shortcuts() {
    find "$DESKTOP_DIR" -maxdepth 1 -name "*.desktop" 2>/dev/null | sort
}

find_existing_by_base() {
    local base_name="$1"
    
    while IFS= read -r -d '' df; do
        local nm=$(desktop_value "$df" "Name")
        [ -z "$nm" ] && continue
        
        local existing_base=$(get_base_name "$nm")
        local new_base=$(get_base_name "$base_name")
        
        if [[ "${existing_base,,}" == "${new_base,,}" ]]; then
            echo "$df"
            return
        fi
    done < <(find "$DESKTOP_DIR" -maxdepth 1 -name "*.desktop" -print0 2>/dev/null)
    
    echo ""
}

is_our_app() {
    local df="$1"
    local ex=$(desktop_value "$df" "Exec")
    local pa=$(desktop_value "$df" "Path")
    
    # Remove root prefix if present
    ex=$(echo "$ex" | sed 's/^pkexec //' | sed 's/^sudo //')
    
    [[ "$ex" == "$APPLICATIONS_DIR/"* ]] && return 0
    [[ "$pa" == "$APPLICATIONS_DIR/"* ]] && return 0
    [[ "$ex" == "$SCRIPT_DIR/"* ]] && return 0
    
    return 1
}

get_installed_version() {
    local name="$1"
    local safe=$(sanitize "$name")
    if [ -f "$DESKTOP_DIR/$safe.desktop" ]; then
        local ver=$(grep -m1 '^X-AppVersion=' "$DESKTOP_DIR/$safe.desktop" 2>/dev/null | cut -d= -f2-)
        [ -n "$ver" ] && [ "$ver" != "Unknown" ] && { echo "$ver"; return; }
    fi
    local version=$(echo "$name" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
    echo "$version"
}

# ------------------------------------------------------------------------------
# EDIT SHORTCUT
# ------------------------------------------------------------------------------

edit_shortcut() {
    local df="$1"

    local name exec icon cat path comment version
    name="$(desktop_value "$df" "Name")"
    exec="$(desktop_value "$df" "Exec")"
    icon="$(desktop_value "$df" "Icon")"
    cat="$(desktop_value "$df" "Categories" | tr -d ';' | cut -d';' -f1)"
    path="$(desktop_value "$df" "Path")"
    comment="$(desktop_value "$df" "Comment")"
    version="$(desktop_value "$df" "X-AppVersion")"

    # Strip root prefix from exec
    exec=$(echo "$exec" | sed 's/^pkexec //' | sed 's/^sudo //')

    [ -z "$cat" ] && cat="Other"
    [ -z "$path" ] && path="$(dirname "$exec")"
    [ -z "$comment" ] && comment="$name"
    
    # Auto-detect version from name if version is unknown
    if [ -z "$version" ] || [ "$version" = "Unknown" ]; then
        version=$(extract_version_from_name "$name")
        [ -z "$version" ] && version="Unknown"
    fi

    local clean_name=$(echo "$name" | sed -E 's/[0-9]+\.[0-9]+(\.[0-9]+)?//g' | sed 's/  / /g' | sed 's/ $//' | sed 's/^ //')
    [ -z "$clean_name" ] && clean_name="$name"
    
    local base_name=$(get_base_name "$name")
    local original_file="$df"

    while true; do
        local cat_disp=$(display_category "$cat")
        local icon_disp="None"
        [ -n "$icon" ] && icon_disp=$(basename "$icon")
        local exec_disp=$(basename "$exec")
        
        clear
        msg "===== EDIT: $clean_name =====" "$CYAN"
        line
        echo ""
        msg "  Version  : $version" "$BLUE"
        echo ""
        echo "  1. Name     : $clean_name"
        echo "  2. File     : $exec_disp"
        echo "  3. Icon     : $icon_disp"
        echo "  4. Category : $cat_disp"
        echo "  5. Comment  : $comment"
        echo "  6. Update from file"
        echo "  7. Save"
        echo ""
        msg "  ↳ Enter (empty) = Back" "$YELLOW"
        line
        echo ""
        printf "Edit (1-7, or press Enter): "
        read c
        
        [ -z "$c" ] && return 0

        case "$c" in
            1)
                printf "New name: "
                read x
                if [ -n "$x" ]; then
                    local new_version=$(extract_version_from_name "$x")
                    
                    name="$x"
                    clean_name=$(echo "$x" | sed -E 's/[0-9]+\.[0-9]+(\.[0-9]+)?//g' | sed 's/  / /g' | sed 's/ $//' | sed 's/^ //')
                    [ -z "$clean_name" ] && clean_name="$x"
                    
                    if [ -n "$new_version" ]; then
                        version="$new_version"
                        msg "  ✓ Version detected: $version" "$GREEN"
                    fi
                fi
                ;;
            2)
                local exec_options=()
                local exec_files=()
                
                while IFS= read -r -d '' f; do
                    local bn=$(basename "$f")
                    local ftype=$(file -b "$f" 2>/dev/null)
                    
                    if [[ "$ftype" == *"ELF"* ]] || [[ "$ftype" == *"script"* ]] || [[ "$bn" == *.sh ]]; then
                        exec_options+=("$bn")
                        exec_files+=("$f")
                    fi
                done < <(find "$path" -maxdepth 1 -type f -executable -print0 2>/dev/null)
                
                while IFS= read -r -d '' f; do
                    local bn=$(basename "$f")
                    if [[ "$bn" == *.sh ]]; then
                        local already=0
                        for existing in "${exec_files[@]}"; do
                            [ "$existing" = "$f" ] && already=1 && break
                        done
                        if [ $already -eq 0 ]; then
                            exec_options+=("$bn (script)")
                            exec_files+=("$f")
                        fi
                    fi
                done < <(find "$path" -maxdepth 1 -type f -name "*.sh" -print0 2>/dev/null)
                
                if [ ${#exec_options[@]} -eq 0 ]; then
                    msg "  No executable files found in $path" "$RED"
                    printf "  Enter path manually: "
                    read x
                    if [ -n "$x" ] && [ -f "$x" ]; then
                        exec="$x"
                        path="$(dirname "$x")"
                        msg "  ✓ Executable updated" "$GREEN"
                    fi
                    sleep 1
                else
                    while true; do
                        clear
                        msg "===== SELECT EXECUTABLE =====" "$CYAN"
                        line
                        echo ""
                        msg "  Current: $exec_disp" "$BLUE"
                        echo ""
                        for i in "${!exec_options[@]}"; do
                            echo "  $((i+1)). ${exec_options[$i]}"
                        done
                        echo ""
                        echo "  0. Cancel"
                        line
                        printf "Select (1-${#exec_options[@]}, 0=Cancel): "
                        read choice
                        
                        if [ "$choice" = "0" ]; then
                            break
                        elif [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le ${#exec_options[@]} ]; then
                            local new_exec="${exec_files[$((choice-1))]}"
                            
                            if [ ! -x "$new_exec" ]; then
                                clear
                                msg "  File is not executable" "$YELLOW"
                                echo ""
                                echo "  1. Make it executable and use it"
                                echo "  2. Use it as-is (might not work)"
                                echo "  3. Cancel"
                                printf "Select (1-3): "
                                read ch
                                case $ch in
                                    1) chmod +x "$new_exec"; exec="$new_exec"; path="$(dirname "$new_exec")"; msg "  ✓ Made executable and updated" "$GREEN"; sleep 1; break ;;
                                    2) exec="$new_exec"; path="$(dirname "$new_exec")"; msg "  ✓ Executable updated" "$YELLOW"; sleep 1; break ;;
                                    3) break ;;
                                esac
                            else
                                exec="$new_exec"
                                path="$(dirname "$new_exec")"
                                msg "  ✓ Executable updated" "$GREEN"
                                sleep 1
                                break
                            fi
                        fi
                    done
                fi
                ;;
            3)
                select_icon "$path" "$clean_name" "edit"
                if [ -n "$ICON_RESULT" ]; then
                    if [[ "$ICON_RESULT" == "$SCRIPT_DIR/"* ]]; then
                        cp "$ICON_RESULT" "$path/$(basename "$ICON_RESULT")"
                        icon="$path/$(basename "$ICON_RESULT")"
                    else
                        icon="$ICON_RESULT"
                    fi
                fi
                ;;
            4)
                select_category && cat="$CATEGORY_RESULT"
                [ -z "$cat" ] && cat="Other"
                ;;
            5)
                printf "New comment: "
                read x
                [ -n "$x" ] && comment="$x"
                ;;
            6)
                load_program_list
                local new_cat=$(lookup_category "$base_name")
                local new_comment=$(lookup_comment "$base_name")
                local new_version=$(lookup_version "$base_name")
                
                if [ -z "$new_cat" ]; then
                    clear
                    msg "  '$base_name' not found in program list" "$YELLOW"
                    pause
                else
                    cat="$new_cat"
                    comment="$new_comment"
                    if [ -n "$new_version" ]; then
                        version="$new_version"
                    elif [ -z "$version" ] || [ "$version" = "Unknown" ]; then
                        version=$(extract_version_from_name "$name")
                        [ -z "$version" ] && version="Unknown"
                    fi
                    msg "  ✓ Updated from list" "$GREEN"
                    sleep 1
                fi
                ;;
            7)
                rm -f "$original_file"
                create_desktop_full "$name" "$exec" "$icon" "$cat" "$path" "$comment" "$version"
                update_db
                msg "  ✓ Saved (runs as root)" "$GREEN"
                pause
                return 0
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# EDIT / REMOVE SHORTCUTS MENUS
# ------------------------------------------------------------------------------

menu_edit_shortcuts() {
    while true; do
        local shortcuts=()
        local shortcut_names=()
        
        while IFS= read -r df; do
            [ -z "$df" ] && continue
            local nm=$(desktop_value "$df" "Name")
            local cat=$(desktop_value "$df" "Categories" | tr -d ';' | cut -d';' -f1)
            shortcuts+=("$df")
            shortcut_names+=("$nm [$(display_category "$cat")]")
        done < <(list_shortcuts)
        
        if [ ${#shortcuts[@]} -eq 0 ]; then
            msg "No shortcuts found" "$YELLOW"
            pause
            return
        fi
        
        show_menu "EDIT SHORTCUT" "${shortcut_names[@]}"
        local choice=$?
        
        case $choice in
            0|255) return ;;
            *)
                local idx=$((choice-1))
                edit_shortcut "${shortcuts[$idx]}"
                ;;
        esac
    done
}

menu_edit_remove_shortcuts() {
    while true; do
        clear
        msg "===== EDIT / REMOVE SHORTCUTS =====" "$CYAN"
        line
        echo ""
        msg "  ↳ Enter (empty) = Back" "$YELLOW"
        echo ""
        echo "  1. Edit a shortcut"
        echo "  2. Remove shortcuts"
        echo ""
        echo "  M. Main Menu"
        line
        echo ""
        printf "Select (1-2, M, or press Enter): "
        read c
        
        [ -z "$c" ] && return
        [ "$c" = "M" ] || [ "$c" = "m" ] && return 0
        
        case $c in
            1) menu_edit_shortcuts ;;
            2) menu_remove_shortcuts ;;
        esac
    done
}

menu_remove_shortcuts() {
    while true; do
        clear
        msg "===== REMOVE SHORTCUTS =====" "$RED"
        line
        echo ""
        msg "  ↳ Enter (empty) = Back" "$YELLOW"
        echo ""
        echo "  1. Automatic (remove all orphan shortcuts)"
        echo "  2. Manual (select from queue)"
        echo ""
        echo "  M. Main Menu"
        line
        echo ""
        printf "Select (1-2, M, or press Enter): "
        read c
        
        [ -z "$c" ] && return
        [ "$c" = "M" ] || [ "$c" = "m" ] && return 0
        
        case $c in
            1) remove_orphan_shortcuts ;;
            2) remove_shortcuts_queue ;;
        esac
    done
}

remove_orphan_shortcuts() {
    clear
    msg "===== REMOVE ORPHAN SHORTCUTS =====" "$RED"
    echo ""
    
    local orphans=()
    while IFS= read -r -d '' df; do
        local ex=$(desktop_value "$df" "Exec")
        ex=$(echo "$ex" | sed 's/^pkexec //' | sed 's/^sudo //')
        local pa=$(desktop_value "$df" "Path")
        
        if [ ! -f "$ex" ]; then
            if [ -z "$pa" ] || [ ! -d "$pa" ]; then
                orphans+=("$df")
            fi
        fi
    done < <(find "$DESKTOP_DIR" -maxdepth 1 -name "*.desktop" -print0 2>/dev/null)
    
    if [ ${#orphans[@]} -eq 0 ]; then
        msg "No orphan shortcuts found" "$GREEN"
        pause
        return
    fi
    
    msg "Found ${#orphans[@]} orphan shortcut(s):" "$YELLOW"
    echo ""
    for df in "${orphans[@]}"; do
        local nm=$(desktop_value "$df" "Name")
        local ex=$(desktop_value "$df" "Exec")
        echo "  - $nm → $ex"
    done
    echo ""
    msg "These shortcuts point to files that no longer exist." "$YELLOW"
    echo ""
    echo "  1. Remove all"
    echo "  2. Cancel"
    printf "Select: "
    read c
    
    if [ "$c" = "1" ]; then
        for df in "${orphans[@]}"; do
            rm -f "$df"
        done
        update_db
        msg "✓ Removed ${#orphans[@]} orphan shortcut(s)" "$GREEN"
    else
        msg "Cancelled" "$YELLOW"
    fi
    
    pause
}

remove_shortcuts_queue() {
    local shortcuts=()
    local display=()
    
    while IFS= read -r df; do
        [ -z "$df" ] && continue
        shortcuts+=("$df")
        local nm=$(desktop_value "$df" "Name")
        local ex=$(desktop_value "$df" "Exec")
        ex=$(echo "$ex" | sed 's/^pkexec //' | sed 's/^sudo //')
        local pa=$(desktop_value "$df" "Path")
        local status=""
        if [ ! -f "$ex" ] && [ ! -d "$pa" ]; then
            status=" ${RED}[ORPHAN]${NC}"
        fi
        display+=("$nm → $(basename "$ex")$status")
    done < <(list_shortcuts)
    
    if [ ${#shortcuts[@]} -eq 0 ]; then
        msg "No shortcuts found" "$YELLOW"
        pause
        return
    fi
    
    local selected=()
    while true; do
        clear
        msg "===== REMOVE SHORTCUTS (Manual) =====" "$RED"
        msg "Selected: ${#selected[@]} item(s)" "$YELLOW"
        echo ""
        msg "  ↳ Enter (empty) = Confirm & Remove" "$YELLOW"
        echo ""
        
        for i in "${!display[@]}"; do
            local marker=""
            for s in "${selected[@]}"; do 
                [ "$s" = "$i" ] && marker=" ${RED}[✓]${NC}" && break
            done
            echo -e "  $((i+1)). ${display[$i]}$marker"
        done
        
        echo ""
        echo "  M. Main Menu"
        echo "  Commands: Numbers (1 3 5), 0=all, c=clear"
        line
        printf "> "
        read input

        if [ -z "$input" ]; then
            if [ ${#selected[@]} -gt 0 ]; then
                break
            else
                return
            fi
        fi
        [ "$input" = "M" ] || [ "$input" = "m" ] && return 0
        [ "$input" = "c" ] && { selected=(); continue; }
        [ "$input" = "0" ] && {
            if [ ${#selected[@]} -eq ${#shortcuts[@]} ]; then
                selected=()
            else
                selected=()
                for i in "${!shortcuts[@]}"; do 
                    selected+=("$i")
                done
            fi
            continue
        }
        
        for num in $input; do
            if [ "$num" -ge 1 ] 2>/dev/null && [ "$num" -le ${#shortcuts[@]} ]; then
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

    if [ ${#selected[@]} -eq 0 ]; then
        return
    fi

    clear
    msg "Removing ${#selected[@]} shortcut(s)..." "$RED"
    echo ""

    local removed=0
    for idx in "${selected[@]}"; do
        local nm=$(desktop_value "${shortcuts[$idx]}" "Name")
        rm -f "${shortcuts[$idx]}"
        msg "  ✓ Removed: $nm" "$GREEN"
        removed=$((removed + 1))
    done

    update_db
    msg "✅ Removed $removed shortcut(s)!" "$GREEN"
    pause
}