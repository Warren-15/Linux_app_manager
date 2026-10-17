# ------------------------------------------------------------------------------
# CATEGORIES - COMPLETE VERSION WITH NORMALIZATION
# ------------------------------------------------------------------------------

CUSTOM_CAT_FILE="$DATA_DIR/custom_categories.txt"

normalize_to_main() {
    local cat=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    [ -z "$cat" ] && { echo "Other"; return; }
    
    # Get all main categories from settings
    local main_cats=()
    while IFS= read -r line; do
        [ -n "$line" ] && main_cats+=("$line")
    done < <(get_main_categories)
    
    # Check each main category's subcategories
    for main_cat in "${main_cats[@]}"; do
        local subs=$(get_subcategories "$main_cat")
        if [ -n "$subs" ]; then
            IFS=',' read -ra sub_arr <<< "$subs"
            for sub in "${sub_arr[@]}"; do
                local lower_sub=$(echo "$sub" | tr '[:upper:]' '[:lower:]' | xargs)
                if [ "$cat" = "$lower_sub" ]; then
                    echo "$main_cat"
                    return
                fi
            done
        fi
    done
    
    # Not found in any category
    echo "Other"
}

# Initialize
init_custom_categories() {
    mkdir -p "$DATA_DIR"
    [ -f "$CUSTOM_CAT_FILE" ] || touch "$CUSTOM_CAT_FILE"
}

save_custom_category() {
    local display_name="$1"
    local internal_name="$2"
    
    init_custom_categories
    if ! grep -q "^$display_name|" "$CUSTOM_CAT_FILE" 2>/dev/null; then
        echo "$display_name|$internal_name" >> "$CUSTOM_CAT_FILE"
    fi
}

remove_custom_category() {
    local display_name="$1"
    
    local internal_name=""
    for i in "${!CUSTOM_NAMES[@]}"; do
        if [ "${CUSTOM_NAMES[$i]}" = "$display_name" ]; then
            internal_name="${CUSTOM_INTERNAL[$i]}"
            break
        fi
    done
    
    if [ -z "$internal_name" ]; then
        return 1
    fi
    
    # Remove .directory file
    local dir_file="$REAL_HOME/.local/share/desktop-directories/${internal_name}.directory"
    [ -f "$dir_file" ] && rm -f "$dir_file"
    
    # Remove .menu file
    local menu_file="$REAL_HOME/.config/menus/applications-merged/${internal_name}.menu"
    [ -f "$menu_file" ] && rm -f "$menu_file"
    
    # Remove from custom categories list
    remove_custom_category_from_file "$display_name"
    
    # Clear cache
    rm -rf "$REAL_HOME/.cache/menus" 2>/dev/null
}

# Add this near the other custom category functions

remove_custom_category_from_file() {
    local display_name="$1"
    init_custom_categories
    if [ -f "$CUSTOM_CAT_FILE" ]; then
        grep -v "^$display_name|" "$CUSTOM_CAT_FILE" > "${CUSTOM_CAT_FILE}.tmp"
        mv "${CUSTOM_CAT_FILE}.tmp" "$CUSTOM_CAT_FILE"
    fi
}

remove_custom_category() {
    local display_name="$1"
    
    local internal_name=""
    load_custom_categories
    for i in "${!CUSTOM_NAMES[@]}"; do
        if [ "${CUSTOM_NAMES[$i]}" = "$display_name" ]; then
            internal_name="${CUSTOM_INTERNAL[$i]}"
            break
        fi
    done
    
    if [ -z "$internal_name" ]; then
        return 1
    fi
    
    # Remove .directory file
    local dir_file="$REAL_HOME/.local/share/desktop-directories/${internal_name}.directory"
    [ -f "$dir_file" ] && rm -f "$dir_file"
    
    # Remove .menu file
    local menu_file="$REAL_HOME/.config/menus/applications-merged/${internal_name}.menu"
    [ -f "$menu_file" ] && rm -f "$menu_file"
    
    # Remove from custom categories list
    remove_custom_category_from_file "$display_name"
    
    # Clear cache
    rm -rf "$REAL_HOME/.cache/menus" 2>/dev/null
}

load_custom_categories() {
    CUSTOM_NAMES=()
    CUSTOM_INTERNAL=()
    
    init_custom_categories
    if [ -f "$CUSTOM_CAT_FILE" ]; then
        while IFS='|' read -r display internal; do
            [ -n "$display" ] && [ -n "$internal" ] && {
                CUSTOM_NAMES+=("$display")
                CUSTOM_INTERNAL+=("$internal")
            }
        done < "$CUSTOM_CAT_FILE"
    fi
}



get_all_raw_categories() {
    local all_cats=()
    
    while IFS= read -r desktop_file; do
        if [ -f "$desktop_file" ]; then
            local cats=$(grep "^Categories=" "$desktop_file" 2>/dev/null | head -1 | cut -d= -f2)
            if [ -n "$cats" ]; then
                IFS=';' read -ra cat_array <<< "$cats"
                for token in "${cat_array[@]}"; do
                    token=$(echo "$token" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                    [ -n "$token" ] && all_cats+=("$token")
                done
            fi
        fi
    done < <(find /usr/share/applications/ "$DESKTOP_DIR" -name "*.desktop" 2>/dev/null)
    
    printf '%s\n' "${all_cats[@]}" | sort -u
}

get_used_main_categories() {
    local used=()
    
    while IFS= read -r raw_cat; do
        local normalized=$(normalize_to_main "$raw_cat")
        if [ "$normalized" != "Other" ]; then
            used+=("$normalized")
        fi
    done < <(get_all_raw_categories)
    
    load_custom_categories
    for i in "${!CUSTOM_NAMES[@]}"; do
        local found=0
        while IFS= read -r desktop_file; do
            if grep -q "Categories=.*${CUSTOM_INTERNAL[$i]}.*;" "$desktop_file" 2>/dev/null; then
                found=1
                break
            fi
        done < <(find "$DESKTOP_DIR" -name "*.desktop" 2>/dev/null)
        if [ $found -eq 1 ]; then
            used+=("${CUSTOM_NAMES[$i]}")
        fi
    done
    
    printf '%s\n' "${used[@]}" | sort -u
}

get_all_main_categories() {
    local all_main=(
        "Accessories"
        "Education"
        "Games"
        "Graphics"
        "Internet"
        "Office"
        "Programming"
        "Sound & Video"
        "System"
        "System Settings"
    )
    
    load_custom_categories
    for name in "${CUSTOM_NAMES[@]}"; do
        if [[ ! " ${all_main[*]} " =~ " ${name} " ]]; then
            all_main+=("$name")
        fi
    done
    
    printf '%s\n' "${all_main[@]}" | sort -u
}

get_active_categories() {
    get_used_main_categories
}

get_hidden_raw_categories() {
    local all_raw=()
    while IFS= read -r dir_file; do
        if [ -f "$dir_file" ]; then
            local name=$(grep "^Name=" "$dir_file" 2>/dev/null | head -1 | cut -d= -f2-)
            [ -n "$name" ] && all_raw+=("$name")
        fi
    done < <(find /usr/share/desktop-directories/ "$REAL_HOME/.local/share/desktop-directories/" -name "*.directory" 2>/dev/null)
    
    local used_main=()
    while IFS= read -r line; do
        [ -n "$line" ] && used_main+=("$line")
    done < <(get_used_main_categories)
    
    local hidden=()
    for raw in "${all_raw[@]}"; do
        case "$raw" in
            "Applications"|"Preferences"|"Administration"|"System Settings"|"Sundry"|"Debian")
                continue ;;
        esac
        
        local normalized=$(normalize_to_main "$raw")
        
        local found=0
        for used in "${used_main[@]}"; do
            if [ "$normalized" = "$used" ]; then
                found=1
                break
            fi
        done
        
        if [ $found -eq 0 ]; then
            hidden+=("$raw")
        fi
    done
    
    load_custom_categories
    for i in "${!CUSTOM_NAMES[@]}"; do
        if is_custom_category_empty "${CUSTOM_INTERNAL[$i]}"; then
            hidden+=("${CUSTOM_NAMES[$i]}")
        fi
    done
    
    printf '%s\n' "${hidden[@]}" | sort -u
}

get_hidden_categories() {
    local used=()
    while IFS= read -r line; do [ -n "$line" ] && used+=("$line"); done < <(get_used_main_categories)
    
    local all_main=()
    while IFS= read -r line; do [ -n "$line" ] && all_main+=("$line"); done < <(get_all_main_categories)
    
    local hidden=()
    for main in "${all_main[@]}"; do
        local found=0
        for u in "${used[@]}"; do
            [ "$u" = "$main" ] && found=1 && break
        done
        [ $found -eq 0 ] && hidden+=("$main")
    done
    
    printf '%s\n' "${hidden[@]}"
}

# ------------------------------------------------------------------------------
# Sanitize category name for internal use (XDG-compliant)
# ------------------------------------------------------------------------------

sanitize_category_name() {
    local name="$1"
    # Remove special characters, replace spaces with nothing, keep only alphanumeric
    echo "$name" | sed 's/[&]//g' | sed 's/[[:space:]]//g' | sed 's/[^a-zA-Z0-9]//g'
}

# ------------------------------------------------------------------------------
# CREATE CUSTOM CATEGORY
# ------------------------------------------------------------------------------

create_custom_category() {
    local display_name="$1"
    [ -z "$display_name" ] && return 1

    # Create internal name (sanitized for XDG)
    local internal_name=$(sanitize_category_name "$display_name")
    
    # Ensure internal name is not empty
    if [ -z "$internal_name" ]; then
        internal_name="Category$(date +%s)"
        msg "  Warning: Using internal name: $internal_name" "$YELLOW"
    fi
    
    local dir_dir="$REAL_HOME/.local/share/desktop-directories"
    local menu_dir="$REAL_HOME/.config/menus/applications-merged"
    local dir_file="$dir_dir/${internal_name}.directory"
    local menu_file="$menu_dir/${internal_name}.menu"
    
    if [ -f "$dir_file" ] && [ -f "$menu_file" ]; then
        msg "  Category '$display_name' already exists" "$YELLOW"
        return 0
    fi

    # 1. Create .directory file
    mkdir -p "$dir_dir"

    # Auto-detect icon from categories_icons.txt
    local icon="folder"
    local lower_name=$(echo "$display_name" | tr '[:upper:]' '[:lower:]')
    local icons_file="$DATA_DIR/categories_icons.txt"
    
    if [ -f "$icons_file" ]; then
        while IFS='=' read -r keywords icon_name; do
            [ -z "$keywords" ] && continue
            IFS='|' read -ra kw_arr <<< "$keywords"
            for kw in "${kw_arr[@]}"; do
                kw=$(echo "$kw" | tr -d ' ')
                if [[ "$lower_name" == *"$kw"* ]] || [[ "$kw" == *"$lower_name"* ]]; then
                    icon="$icon_name"
                    break 2
                fi
            done
        done < "$icons_file"
    fi
    
    cat > "$dir_file" << EOF
[Desktop Entry]
Type=Directory
Name=$display_name
Icon=$icon
EOF

    # 2. Create .menu file
    mkdir -p "$menu_dir"
    cat > "$menu_file" << EOF
<!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN"
 "http://www.freedesktop.org/standards/menu-spec/menu-1.0.dtd">

<Menu>
    <Name>Applications</Name>
    <Menu>
        <Name>$internal_name</Name>
        <Directory>${internal_name}.directory</Directory>
        <Include>
            <Category>$internal_name</Category>
        </Include>
    </Menu>
</Menu>
EOF

    # 3. Save custom category (store both display name and internal name)
    save_custom_category "$display_name" "$internal_name"
    
    # 4. Fix ownership if sudo
    if [ "$EUID" -eq 0 ]; then
        chown -R "$REAL_USER:$REAL_USER" "$dir_file" "$menu_file" 2>/dev/null
    fi
    
    # 5. Clear menu cache and refresh
    rm -rf "$REAL_HOME/.cache/menus" 2>/dev/null
    update-desktop-database "$DESKTOP_DIR" 2>/dev/null
    xdg-desktop-menu forceupdate 2>/dev/null
    
    msg "  ✓ Category '$display_name' created" "$GREEN"
    msg "    (Internal name: $internal_name)" "$BLUE"
}

create_category_standalone() {
    clear
    msg "===== CREATE CUSTOM CATEGORY =====" "$CYAN"
    line
    echo ""
    msg "  ↳ Enter (empty) = Back" "$YELLOW"
    echo ""
    printf "  Category name: "
    read display_name
    
    if [ -z "$display_name" ]; then
        msg "  Cancelled" "$YELLOW"
        sleep 1
        return
    fi
    
    create_custom_category "$display_name"
    pause
}

# ------------------------------------------------------------------------------
# CHECK IF CUSTOM CATEGORY HAS ITEMS
# ------------------------------------------------------------------------------

is_custom_category_empty() {
    local internal_name="$1"
    
    while IFS= read -r desktop_file; do
        if grep -q "^Categories=.*$internal_name.*;" "$desktop_file" 2>/dev/null; then
            return 1  # Not empty
        fi
    done < <(find "$DESKTOP_DIR" -name "*.desktop" 2>/dev/null)
    
    return 0  # Empty
}

normalize_category() {
    normalize_to_main "$1"
}

display_category() {
    local val="$1"
    [ -z "$val" ] && { echo "Other"; return; }
    
    # First try to normalize it
    local normalized=$(normalize_to_main "$val")
    if [ "$normalized" != "Other" ]; then
        echo "$normalized"
        return
    fi
    
    # Check custom categories
    load_custom_categories
    for i in "${!CUSTOM_NAMES[@]}"; do
        [ "${CUSTOM_INTERNAL[$i]}" = "$val" ] && { echo "${CUSTOM_NAMES[$i]}"; return; }
    done
    
    echo "$val"
}

CATEGORY_CACHE="$DATA_DIR/categories.cache"

load_category_cache() {
    if [ -f "$CATEGORY_CACHE" ]; then
        source "$CATEGORY_CACHE"
        _CATS_CACHED=1
        return 0
    fi
    return 1
}

save_category_cache() {
    mkdir -p "$DATA_DIR"
    {
        echo "_ACTIVE_CATS=("
        for item in "${_ACTIVE_CATS[@]}"; do
            echo "  \"$item\""
        done
        echo ")"
        echo "_HIDDEN_CATS=("
        for item in "${_HIDDEN_CATS[@]}"; do
            echo "  \"$item\""
        done
        echo ")"
    } > "$CATEGORY_CACHE"
}
# ==============================================================================
# PROGRAM LIST FUNCTIONS
# ==============================================================================

# Cache file for program list - persistent across reboots
PROGRAM_CACHE="$DATA_DIR/list.cache"

load_program_list() {
    PROG_NAMES=()
    PROG_CATEGORIES=()
    PROG_DESCRIPTIONS=()
    PROG_FORMATS=()
    PROG_SOURCES=()
    PROG_VERSIONS=()
    PROG_URLS=()

    if [ ! -f "$PROGRAM_LIST" ]; then
        msg "  Program list file not found: $PROGRAM_LIST" "$YELLOW"
        return
    fi

    # استخدام awk لتجاهل التعليقات والأسطر الفارغة
    local raw_data
    raw_data=$(awk -F '\t' '!/^[[:space:]]*#/ && NF>=6 {printf "%s|%s|%s|%s|%s|%s\n", $1, $2, $3, $4, $5, $6}' "$PROGRAM_LIST")

    while IFS='|' read -r name cat desc fmt src url; do
        name=$(echo "$name" | xargs)
        cat=$(echo "$cat" | xargs)
        desc=$(echo "$desc" | xargs)
        fmt=$(echo "$fmt" | xargs)
        src=$(echo "$src" | xargs)
        url=$(echo "$url" | xargs)

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
        PROG_VERSIONS+=("")
    done <<< "$raw_data"

    if [ ${#PROG_NAMES[@]} -eq 0 ]; then
        msg "  No valid entries found in $PROGRAM_LIST" "$RED"
    else
        msg "  Loaded ${#PROG_NAMES[@]} programs from list." "$GREEN"
    fi
}

lookup_source() {
    local app_name="$1"
    local lower_app=$(echo "$app_name" | tr '[:upper:]' '[:lower:]')
    for i in "${!PROG_NAMES[@]}"; do
        local lower_prog=$(echo "${PROG_NAMES[$i]}" | tr '[:upper:]' '[:lower:]')
        if [[ "$lower_app" == *"$lower_prog"* ]] || [[ "$lower_prog" == *"$lower_app"* ]]; then
            echo "${PROG_SOURCES[$i]}"
            return
        fi
    done
    echo "folder"
}

lookup_format() {
    local app_name="$1"
    local lower_app=$(echo "$app_name" | tr '[:upper:]' '[:lower:]')
    for i in "${!PROG_NAMES[@]}"; do
        local lower_prog=$(echo "${PROG_NAMES[$i]}" | tr '[:upper:]' '[:lower:]')
        if [[ "$lower_app" == *"$lower_prog"* ]] || [[ "$lower_prog" == *"$lower_app"* ]]; then
            echo "${PROG_FORMATS[$i]}"
            return
        fi
    done
    echo "AppImage"
}

lookup_category() {
    local app_name="$1"
    local lower_app=$(echo "$app_name" | tr '[:upper:]' '[:lower:]')
    
    for i in "${!PROG_NAMES[@]}"; do
        local lower_prog=$(echo "${PROG_NAMES[$i]}" | tr '[:upper:]' '[:lower:]')
        if [[ "$lower_app" == *"$lower_prog"* ]] || [[ "$lower_prog" == *"$lower_app"* ]]; then
            echo "${PROG_CATEGORIES[$i]}"
            return
        fi
    done
    echo ""
}

lookup_description() {
    local app_name="$1"
    local lower_app=$(echo "$app_name" | tr '[:upper:]' '[:lower:]')
    
    for i in "${!PROG_NAMES[@]}"; do
        local lower_prog=$(echo "${PROG_NAMES[$i]}" | tr '[:upper:]' '[:lower:]')
        if [[ "$lower_app" == *"$lower_prog"* ]] || [[ "$lower_prog" == *"$lower_app"* ]]; then
            echo "${PROG_DESCRIPTIONS[$i]}"
            return
        fi
    done
    echo ""
}

lookup_version() {
    local app_name="$1"
    local lower_app=$(echo "$app_name" | tr '[:upper:]' '[:lower:]')
    
    for i in "${!PROG_NAMES[@]}"; do
        local lower_prog=$(echo "${PROG_NAMES[$i]}" | tr '[:upper:]' '[:lower:]')
        if [[ "$lower_app" == *"$lower_prog"* ]] || [[ "$lower_prog" == *"$lower_app"* ]]; then
            echo "${PROG_VERSIONS[$i]}"
            return
        fi
    done
    echo ""
}

lookup_url() {
    local app_name="$1"
    local lower_app=$(echo "$app_name" | tr '[:upper:]' '[:lower:]')
    
    for i in "${!PROG_NAMES[@]}"; do
        local lower_prog=$(echo "${PROG_NAMES[$i]}" | tr '[:upper:]' '[:lower:]')
        if [[ "$lower_app" == *"$lower_prog"* ]] || [[ "$lower_prog" == *"$lower_app"* ]]; then
            echo "${PROG_URLS[$i]}"
            return
        fi
    done
    echo ""
}



# Aliases for compatibility
lookup_comment() {
    lookup_description "$1"
}
# Category selection menu
select_category() {
    # Cache categories on first call
    if [ -z "${_CATS_CACHED}" ]; then
        load_category_cache
    fi
    
    if [ -z "${_CATS_CACHED}" ]; then
        msg "  Building category list (first run may take a moment)..." "$YELLOW"
        _ACTIVE_CATS=()
        while IFS= read -r line; do
            [ -n "$line" ] && _ACTIVE_CATS+=("$line")
        done < <(get_active_categories)
        
        # Separate standard and custom categories
        local standard_cats=()
        local custom_cats=()
        for cat in "${_ACTIVE_CATS[@]}"; do
            case "$cat" in
                "Accessories"|"Games"|"Graphics"|"Internet"|"Office"|"Programming"|"Sound & Video"|"System"|"Other"|"Education"|"System Settings")
                    standard_cats+=("$cat") ;;
                *)  custom_cats+=("$cat") ;;
            esac
        done
        
        # Sort standard, keep custom as-is
        IFS=$'\n' standard_cats=($(sort <<<"${standard_cats[*]}"))
        unset IFS
        
        # Add custom categories that aren't already in the list
        load_custom_categories
        for i in "${!CUSTOM_NAMES[@]}"; do
            if ! is_custom_category_empty "${CUSTOM_INTERNAL[$i]}"; then
                if [[ ! " ${standard_cats[*]} ${custom_cats[*]} " =~ " ${CUSTOM_NAMES[$i]} " ]]; then
                    custom_cats+=("${CUSTOM_NAMES[$i]}")
                fi
            fi
        done
        
        # Combine: standard first, then custom
        _ACTIVE_CATS=("${standard_cats[@]}" "${custom_cats[@]}")
        [ ${#_ACTIVE_CATS[@]} -eq 0 ] && _ACTIVE_CATS=("Other")
        
        _HIDDEN_CATS=()
        while IFS= read -r line; do
            [ -n "$line" ] && _HIDDEN_CATS+=("$line")
        done < <(get_hidden_raw_categories)
        
        _CATS_CACHED=1
        save_category_cache
    fi
    
    while true; do
        local options=("${_ACTIVE_CATS[@]}")
        options+=("Select from other categories")
        options+=("Create and set new category")
        
        show_menu "SELECT CATEGORY" "${options[@]}"
        local choice=$?
        
        case $choice in
            0) return 1 ;;
            255) return 1 ;;
        esac
        
        if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le ${#_ACTIVE_CATS[@]} ]; then
            CATEGORY_RESULT="${_ACTIVE_CATS[$((choice-1))]}"
            return 0
        fi
        
        local hidden_option=$(( ${#_ACTIVE_CATS[@]} + 1 ))
        local create_option=$(( ${#_ACTIVE_CATS[@]} + 2 ))
        
        if [ "$choice" = "$hidden_option" ]; then
            if [ ${#_HIDDEN_CATS[@]} -eq 0 ]; then
                msg "  No hidden categories found!" "$YELLOW"
                sleep 1
                continue
            fi
            
            show_menu "SELECT HIDDEN CATEGORY" "${_HIDDEN_CATS[@]}"
            local hidden_choice=$?
            
            case $hidden_choice in
                0|255) continue ;;
                *)
                    CATEGORY_RESULT="${_HIDDEN_CATS[$((hidden_choice-1))]}"
                    local selected_cat="$CATEGORY_RESULT"
                    local internal_name=$(echo "$selected_cat" | sed 's/[^a-zA-Z0-9]//g')
                    local dir_dir="$REAL_HOME/.local/share/desktop-directories"
                    local dir_file="$dir_dir/${internal_name}.directory"
                    
                    if [ ! -f "$dir_file" ]; then
                        mkdir -p "$dir_dir"
                        cat > "$dir_file" << EOF
[Desktop Entry]
Name=$selected_cat
Type=Directory
EOF
                        [ "$EUID" -eq 0 ] && chown -R "$REAL_USER:$REAL_USER" "$dir_dir"
                        save_custom_category "$selected_cat" "$internal_name"
                    fi
                    
                    unset _CATS_CACHED
                    rm -f "$CATEGORY_CACHE"
                    return 0
                    ;;
            esac
        fi
        
        if [ "$choice" = "$create_option" ]; then
            printf "  New category name: "
            IFS= read -r new_cat
            if [ -n "$new_cat" ]; then
                create_custom_category "$new_cat"
                CATEGORY_RESULT="$new_cat"
                unset _CATS_CACHED
                rm -f "$CATEGORY_CACHE"
                return 0
            fi
        fi
    done
}

# ==============================================================================
# CREATE / EDIT CATEGORY MENU
# ==============================================================================

menu_create_edit_category() {
    while true; do
        clear
        msg "===== CREATE / EDIT CATEGORY =====" "$CYAN"
        line
        echo ""
        msg "  ↳ Enter (empty) = Back" "$YELLOW"
        echo ""
        echo "  1. Create New Category"
        echo "  2. Edit Existing Category"
        echo ""
        line
        echo ""
        printf "Select (1-2, or press Enter): "
        IFS= read -r choice
        choice=$(echo "$choice" | tr -d '\r' | xargs)
        
        [ -z "$choice" ] && return
        
        case "$choice" in
            1) create_category_with_items ;;
            2) edit_category_menu ;;
            *) msg "  Invalid choice (1-2)" "$RED"; sleep 1 ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# CREATE CATEGORY WITH ITEMS (Updated to show both names)
# ------------------------------------------------------------------------------

create_category_with_items() {
    clear
    msg "===== CREATE CATEGORY =====" "$CYAN"
    line
    echo ""
    msg "  Note: Category name will be sanitized for internal use" "$YELLOW"
    msg "  (Spaces & special characters like & will be removed internally)" "$YELLOW"
    echo ""
    
    printf "  Category name: "
    IFS= read -r display_name
    
    if [ -z "$display_name" ]; then
        msg "  Cancelled" "$YELLOW"
        pause
        return
    fi
    
    # Show the sanitized name that will be used internally
    local suggested_internal=$(sanitize_category_name "$display_name")
    if [ "$suggested_internal" != "$display_name" ]; then
        echo ""
        msg "  Internal name will be: $suggested_internal" "$BLUE"
    fi
    
    # Check if category already exists
    load_custom_categories
    local existing_internal=$(sanitize_category_name "$display_name")
    for i in "${!CUSTOM_INTERNAL[@]}"; do
        if [ "${CUSTOM_INTERNAL[$i]}" = "$existing_internal" ]; then
            msg "  Category with internal name '$existing_internal' already exists!" "$RED"
            msg "  Existing display name: ${CUSTOM_NAMES[$i]}" "$YELLOW"
            pause
            return
        fi
    done
    
    # Create the category
    create_custom_category "$display_name"
    
    # Get internal name (after creation)
    local internal_name=$(sanitize_category_name "$display_name")
    
    # Now select shortcuts to add to this category
    select_shortcuts_for_category "$internal_name" "$display_name"
    
    pause
}

# ------------------------------------------------------------------------------
# EDIT CATEGORY MENU
# ------------------------------------------------------------------------------

edit_category_menu() {
    load_custom_categories
    
    if [ ${#CUSTOM_NAMES[@]} -eq 0 ]; then
        msg "  No custom categories found. Create one first." "$YELLOW"
        pause
        return
    fi
    
    while true; do
        clear
        msg "===== EDIT CATEGORY =====" "$CYAN"
        line
        echo ""
        
        for i in "${!CUSTOM_NAMES[@]}"; do
            local internal="${CUSTOM_INTERNAL[$i]}"
            if is_custom_category_empty "$internal"; then
                printf "  %d. " $((i+1))
                msg "${CUSTOM_NAMES[$i]}" "$YELLOW"
                msg "     [empty]" "$YELLOW"
            else
                echo "  $((i+1)). ${CUSTOM_NAMES[$i]}"
            fi
        done
        
        echo ""
        echo "  0. Back"
        line
        printf "Select category to edit (1-${#CUSTOM_NAMES[@]}, 0=Back): "
        IFS= read -r choice
        choice=$(echo "$choice" | tr -d '\r' | xargs)
        
        [ -z "$choice" ] && return
        [ "$choice" = "0" ] && return
        
        if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le ${#CUSTOM_NAMES[@]} ]; then
            local idx=$((choice-1))
            local cat_name="${CUSTOM_NAMES[$idx]}"
            local internal_name="${CUSTOM_INTERNAL[$idx]}"
            edit_single_category "$cat_name" "$internal_name"
        fi
    done
}

# ------------------------------------------------------------------------------
# EDIT SINGLE CATEGORY
# ------------------------------------------------------------------------------

edit_single_category() {
    local cat_name="$1"
    local internal_name="$2"
    
    while true; do
        clear
        msg "===== EDIT CATEGORY: $cat_name =====" "$CYAN"
        line
        echo ""
        echo "  1. Rename Category"
        echo "  2. Select Items (add/remove shortcuts)"
        echo ""
        echo "  0. Back"
        line
        printf "Select (1-2, 0=Back): "
        IFS= read -r choice
        choice=$(echo "$choice" | tr -d '\r' | xargs)
        
        [ -z "$choice" ] && return
        [ "$choice" = "0" ] && return
        
        case "$choice" in
            1) rename_category "$cat_name" "$internal_name" ;;
            2) select_shortcuts_for_category "$internal_name" "$cat_name" ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# RENAME CATEGORY
# ------------------------------------------------------------------------------

rename_category() {
    local old_display_name="$1"
    local old_internal_name="$2"
    
    clear
    msg "===== RENAME CATEGORY =====" "$CYAN"
    line
    echo ""
    msg "  Current: $old_display_name" "$BLUE"
    echo ""
    printf "  New name: "
    IFS= read -r new_display_name
    
    if [ -z "$new_display_name" ]; then
        msg "  Cancelled" "$YELLOW"
        pause
        return
    fi
    
    if [ "$new_display_name" = "$old_display_name" ]; then
        msg "  Name unchanged" "$YELLOW"
        pause
        return
    fi
    
    # Create new internal name from new display name
    local new_internal_name=$(sanitize_category_name "$new_display_name")
    
    # Check if new internal name already exists and is different from old
    load_custom_categories
    for i in "${!CUSTOM_NAMES[@]}"; do
        if [ "${CUSTOM_INTERNAL[$i]}" = "$new_internal_name" ] && [ "${CUSTOM_INTERNAL[$i]}" != "$old_internal_name" ]; then
            msg "  Category with internal name '$new_internal_name' already exists!" "$RED"
            msg "  Try a different name (avoid spaces and special characters)" "$YELLOW"
            pause
            return
        fi
    done
    
    # Update .directory file
    local dir_file="$REAL_HOME/.local/share/desktop-directories/${old_internal_name}.directory"
    local new_dir_file="$REAL_HOME/.local/share/desktop-directories/${new_internal_name}.directory"
    
    if [ -f "$dir_file" ]; then
        # Update the Name field in .directory file
        sed -i "s/^Name=.*/Name=$new_display_name/" "$dir_file"
        # Rename the file
        mv "$dir_file" "$new_dir_file"
    fi
    
    # Update .menu file
    local menu_file="$REAL_HOME/.config/menus/applications-merged/${old_internal_name}.menu"
    local new_menu_file="$REAL_HOME/.config/menus/applications-merged/${new_internal_name}.menu"
    
    if [ -f "$menu_file" ]; then
        # Update the Menu name and Directory reference
        sed -i "s/<Name>$old_internal_name<\/Name>/<Name>$new_internal_name<\/Name>/" "$menu_file"
        sed -i "s/<Directory>${old_internal_name}.directory<\/Directory>/<Directory>${new_internal_name}.directory<\/Directory>/" "$menu_file"
        mv "$menu_file" "$new_menu_file"
    fi
    
    # Update all .desktop files that use this category
    local updated=0
    while IFS= read -r desktop_file; do
        if grep -q "^Categories=.*$old_internal_name.*;" "$desktop_file" 2>/dev/null; then
            sed -i "s/$old_internal_name/$new_internal_name/g" "$desktop_file"
            updated=$((updated + 1))
        fi
    done < <(find "$DESKTOP_DIR" -name "*.desktop" 2>/dev/null)
    
    # Update custom categories file
    remove_custom_category_from_file "$old_display_name"
    save_custom_category "$new_display_name" "$new_internal_name"
    
    # Clear cache
    rm -rf "$REAL_HOME/.cache/menus" 2>/dev/null
    rm -f "$CATEGORY_CACHE" 2>/dev/null
    unset _CATS_CACHED
    update-desktop-database "$DESKTOP_DIR" 2>/dev/null
    
    msg "  ✓ Category renamed: $old_display_name → $new_display_name" "$GREEN"
    msg "    (Internal: $old_internal_name → $new_internal_name)" "$BLUE"
    msg "  ✓ Updated $updated shortcut(s)" "$GREEN"
    pause
}

# ------------------------------------------------------------------------------
# SELECT SHORTCUTS FOR CATEGORY
# ------------------------------------------------------------------------------

select_shortcuts_for_category() {
    local internal_name="$1"
    local display_name="$2"
    
    # Get all shortcuts (only our apps from /Applications)
    local shortcuts=()
    local shortcut_names=()
    local shortcut_files=()
    
    while IFS= read -r df; do
        [ -z "$df" ] && continue
        
        # Only include shortcuts from our Applications directory
        local ex=$(desktop_value "$df" "Exec")
        local pa=$(desktop_value "$df" "Path")
        
        if [[ "$ex" == "$APPLICATIONS_DIR/"* ]] || [[ "$pa" == "$APPLICATIONS_DIR/"* ]]; then
            local nm=$(desktop_value "$df" "Name")
            
            shortcuts+=("$df")
            shortcut_names+=("$nm")
            shortcut_files+=("$df")
        fi
    done < <(list_shortcuts)
    
    if [ ${#shortcuts[@]} -eq 0 ]; then
        msg "  No shortcuts found in $APPLICATIONS_DIR" "$YELLOW"
        pause
        return
    fi
    
    # Determine currently selected shortcuts
    local selected=()
    for i in "${!shortcuts[@]}"; do
        local current_cat=$(desktop_value "${shortcuts[$i]}" "Categories" | tr -d ';' | cut -d';' -f1)
        if [ "$current_cat" = "$internal_name" ]; then
            selected+=("$i")
        fi
    done
    
    while true; do
        clear
        msg "===== CATEGORY: $display_name =====" "$CYAN"
        msg "Selected: ${#selected[@]} shortcut(s)" "$YELLOW"
        echo ""
        msg "  Note: Empty categories won't appear in menu" "$BLUE"
        msg "  Unchecked items will be moved to 'Other'" "$YELLOW"
        echo ""
        
        for i in "${!shortcut_names[@]}"; do
            local marker=""
            for s in "${selected[@]}"; do 
                [ "$s" = "$i" ] && marker=" ${GREEN}[✓]${NC}" && break
            done
            echo -e "  $((i+1)). ${shortcut_names[$i]}$marker"
        done
        
        echo ""
        echo "  Commands: Numbers (1 3 5), 0=all, Enter=save, c=clear"
        echo "  M. Main Menu"
        line
        printf "> "
        IFS= read -r input
        input=$(echo "$input" | tr -d '\r' | xargs)
        
        [ "$input" = "M" ] || [ "$input" = "m" ] && return 0
        
        if [ -z "$input" ]; then
            break
        fi
        
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
    
    # Apply changes
    clear
    msg "===== APPLYING CHANGES =====" "$CYAN"
    echo ""
    
    local updated=0
    local moved_to_other=0
    
    for i in "${!shortcuts[@]}"; do
        local df="${shortcuts[$i]}"
        local nm="${shortcut_names[$i]}"
        local is_selected=0
        
        for s in "${selected[@]}"; do
            [ "$s" = "$i" ] && is_selected=1 && break
        done
        
        local current_cat=$(desktop_value "$df" "Categories" | tr -d ';' | cut -d';' -f1)
        
        if [ $is_selected -eq 1 ]; then
            # Add to this category
            if [ "$current_cat" != "$internal_name" ]; then
                # Get all other fields
                local exec_val=$(desktop_value "$df" "Exec")
                local icon_val=$(desktop_value "$df" "Icon")
                local comment_val=$(desktop_value "$df" "Comment")
                local version_val=$(desktop_value "$df" "X-AppVersion")
                local path_val=$(desktop_value "$df" "Path")
                local name_val=$(desktop_value "$df" "Name")
                
                rm -f "$df"
                create_desktop_full "$name_val" "$exec_val" "$icon_val" "$internal_name" "$path_val" "$comment_val" "$version_val"
                msg "  ✓ $nm → $display_name" "$GREEN"
                updated=$((updated + 1))
            fi
        else
            # Not selected - move to "Other" (not empty, just default)
            if [ "$current_cat" = "$internal_name" ]; then
                local exec_val=$(desktop_value "$df" "Exec")
                local icon_val=$(desktop_value "$df" "Icon")
                local comment_val=$(desktop_value "$df" "Comment")
                local version_val=$(desktop_value "$df" "X-AppVersion")
                local path_val=$(desktop_value "$df" "Path")
                local name_val=$(desktop_value "$df" "Name")
                
                rm -f "$df"
                create_desktop_full "$name_val" "$exec_val" "$icon_val" "Other" "$path_val" "$comment_val" "$version_val"
                msg "  ⤏ $nm → Other" "$YELLOW"
                moved_to_other=$((moved_to_other + 1))
            fi
        fi
    done
    
    # Force update database and clear caches
    update_db
    
    # Small delay to ensure files are written
    sleep 1
    
    # Clear the category cache to force refresh
    rm -f "$CATEGORY_CACHE" 2>/dev/null
    unset _CATS_CACHED
    
    echo ""
    msg "═══════════════════════════════════════" "$CYAN"
    [ $updated -gt 0 ] && msg "  ✓ $updated shortcut(s) added to $display_name" "$GREEN"
    [ $moved_to_other -gt 0 ] && msg "  ⤏ $moved_to_other shortcut(s) moved to Other" "$YELLOW"
    msg "═══════════════════════════════════════" "$CYAN"
    
    # DEBUG: Show what's actually in the desktop files
    echo ""
    msg "  [DEBUG] Checking category: $internal_name" "$BLUE"
    local actual_count=0
    while IFS= read -r desktop_file; do
        if grep -q "^Categories=.*$internal_name.*;" "$desktop_file" 2>/dev/null; then
            local nm=$(desktop_value "$desktop_file" "Name")
            msg "    Found: $nm" "$GREEN"
            actual_count=$((actual_count + 1))
        fi
    done < <(find "$DESKTOP_DIR" -name "*.desktop" 2>/dev/null)
    
    msg "    Total shortcuts with category '$internal_name': $actual_count" "$BLUE"
    
    if [ $actual_count -eq 0 ]; then
        echo ""
        msg "  ⚠️  Category has no shortcuts! It won't appear in menus." "$YELLOW"
        msg "  Possible cause: Category name mismatch in .desktop files" "$RED"
        
        # Show what categories are actually in the files
        msg "  [DEBUG] Categories found in .desktop files:" "$BLUE"
        grep -h "^Categories=" "$DESKTOP_DIR"/*.desktop 2>/dev/null | sort -u | head -10 | while read line; do
            msg "    $line" "$BLUE"
        done
    else
        echo ""
        msg "  ✓ Category '$display_name' now has $actual_count shortcut(s)" "$GREEN"
    fi
    
    pause
}
