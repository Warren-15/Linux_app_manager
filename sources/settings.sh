# ==============================================================================
# SETTINGS - WITH ARCHITECTURE SELECTION
# ==============================================================================

SETTINGS_FILE="$DATA_DIR/settings.conf"

# Default directories
DEFAULT_APPS_DIR="/Applications"
DEFAULT_DOWNLOADS_DIR="$SCRIPT_DIR/Download"
DEFAULT_ICONS_DIR="$SCRIPT_DIR/icons"

# Default category
DEFAULT_MAIN_CATEGORY="Other"

# Default architecture (auto-detect)
DEFAULT_ARCHITECTURE="auto"

# Load settings from config file
load_settings() {
    [ ! -f "$SETTINGS_FILE" ] && return
    
    while IFS='=' read -r key value; do
        [ -z "$key" ] && continue
        [[ "$key" == \#* ]] && continue
        
        case "$key" in
            APPLICATIONS_DIR) APPLICATIONS_DIR="$value" ;;
            DOWNLOADS_DIR) DOWNLOADS_DIR="$value" ;;
            ICONS_DIR) ICONS_DIR="$value" ;;
            DEFAULT_CATEGORY) DEFAULT_MAIN_CATEGORY="$value" ;;
            ARCHITECTURE) ARCHITECTURE="$value" ;;
        esac
    done < "$SETTINGS_FILE"
    
    # Also load subcategory mappings
    NORMALIZE_MAP=()
    while IFS='=' read -r key value; do
        [ -z "$key" ] && continue
        [[ "$key" == \#* ]] && continue
        
        # Keys like GRAPHICS=gimp,krita,inkscape become normalize entries
        case "$key" in
            APPLICATIONS_DIR|DOWNLOADS_DIR|ICONS_DIR|DEFAULT_CATEGORY|ARCHITECTURE) ;;
            *) NORMALIZE_MAP+=("$key=$value") ;;
        esac
    done < "$SETTINGS_FILE"
    
    # Set default if not set
    [ -z "$ARCHITECTURE" ] && ARCHITECTURE="auto"
}

# Save settings to config file
save_settings() {
    mkdir -p "$DATA_DIR"
    
    cat > "$SETTINGS_FILE" <<EOF
# Applications Manager Settings
APPLICATIONS_DIR=$APPLICATIONS_DIR
DOWNLOADS_DIR=$DOWNLOADS_DIR
ICONS_DIR=$ICONS_DIR
DEFAULT_CATEGORY=$DEFAULT_MAIN_CATEGORY
ARCHITECTURE=$ARCHITECTURE
EOF
    
    # Save subcategory mappings
    for entry in "${NORMALIZE_MAP[@]}"; do
        echo "$entry" >> "$SETTINGS_FILE"
    done
}

# Get default subcategories for a main category
get_subcategories() {
    local main_cat="$1"
    local cat_key=$(echo "$main_cat" | tr '[:lower:] ' '[:upper:]_' | sed 's/&//g')
    
    for entry in "${NORMALIZE_MAP[@]}"; do
        local key="${entry%%=*}"
        local val="${entry#*=}"
        if [ "$key" = "$cat_key" ]; then
            echo "$val"
            return
        fi
    done
    
    # Return default based on category
    case "$main_cat" in
        "Graphics") echo "graphics,drawing,paint,image" ;;
        "Internet") echo "network,internet,web,chat,email,browser" ;;
        "Sound & Video") echo "audiovideo,media,video,audio,music,player,sound" ;;
        "Office") echo "office,word,spreadsheet,text" ;;
        "Games") echo "game,emulator" ;;
        "Programming") echo "development,ide,editor,debugger" ;;
        "System") echo "system,settings,admin" ;;
        "Accessories") echo "utility,accessories" ;;
        *) echo "" ;;
    esac
}

# Set subcategories for a main category
set_subcategories() {
    local main_cat="$1"
    local subs="$2"
    local cat_key=$(echo "$main_cat" | tr '[:lower:] ' '[:upper:]_' | sed 's/&//g')
    
    local new_map=()
    local found=0
    for entry in "${NORMALIZE_MAP[@]}"; do
        local key="${entry%%=*}"
        if [ "$key" = "$cat_key" ]; then
            new_map+=("$cat_key=$subs")
            found=1
        else
            new_map+=("$entry")
        fi
    done
    [ $found -eq 0 ] && new_map+=("$cat_key=$subs")
    NORMALIZE_MAP=("${new_map[@]}")
    
    save_settings
}

# Get all main categories
get_main_categories() {
    echo "Graphics"
    echo "Internet"
    echo "Sound & Video"
    echo "Office"
    echo "Games"
    echo "Programming"
    echo "System"
    echo "Accessories"
    echo "Other"
}

# ==============================================================================
# SYSTEM ARCHITECTURE DETECTION
# ==============================================================================

get_system_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)
            echo "x86_64"
            ;;
        aarch64|arm64)
            echo "aarch64"
            ;;
        armv7l|armv7|armhf)
            echo "armv7"
            ;;
        armv6l)
            echo "armv6"
            ;;
        *)
            echo "$arch"
            ;;
    esac
}

get_target_architecture() {
    if [ "$ARCHITECTURE" = "auto" ]; then
        get_system_arch
    else
        echo "$ARCHITECTURE"
    fi
}

is_architecture_match() {
    local filename="$1"
    local lower=$(echo "$filename" | tr '[:upper:]' '[:lower:]')
    local target_arch=$(get_target_architecture)
    
    if [ "$ARCHITECTURE" = "auto" ]; then
        return 0
    fi
    
    case "$target_arch" in
        x86_64)
            if [[ "$lower" =~ (x86_64|amd64) ]]; then
                return 0
            fi
            if [[ "$lower" =~ (arm64|aarch64|armv7|armhf) ]]; then
                return 1
            fi
            return 1
            ;;
        aarch64|arm64)
            if [[ "$lower" =~ (arm64|aarch64) ]]; then
                return 0
            fi
            return 1
            ;;
        armv7)
            if [[ "$lower" =~ (armv7|armhf) ]]; then
                return 0
            fi
            return 1
            ;;
        *) return 0 ;;
    esac
}

get_architecture_score() {
    local filename="$1"
    local lower=$(echo "$filename" | tr '[:upper:]' '[:lower:]')
    
    if [ "$ARCHITECTURE" = "auto" ]; then
        if [[ "$lower" =~ (arm64|aarch64|armv7|armhf|raspberry|rpi) ]]; then
            echo "-5000"
            return
        fi
        if [[ "$lower" =~ (x86_64|amd64) ]]; then
            echo "80"
            return
        fi
        echo "0"
        return
    fi
    
    if is_architecture_match "$filename"; then
        echo "500"
    else
        echo "-9999"
    fi
}

# ==============================================================================
# SETTINGS MENU
# ==============================================================================

menu_settings() {
    while true; do
        clear
        msg "╔══════════════════════════════════════════════╗" "$CYAN"
        msg "║              SETTINGS                        ║" "$CYAN"
        msg "╚══════════════════════════════════════════════╝" "$CYAN"
        echo ""
        msg "  Current Architecture: $ARCHITECTURE" "$BLUE"
        msg "  System Architecture: $(get_system_arch)" "$GREEN"
        echo ""
        msg "  ↳ Enter (empty) = Back" "$YELLOW"
        echo ""
        echo "  ┌────────────────────────────────────────────┐"
        echo "  │  1. Change Directories                    │"
        echo "  │  2. Category Normalization                │"
        echo "  │  3. Default Category                      │"
        echo "  │  4. Set Download File Architecture        │"
        echo "  └────────────────────────────────────────────┘"
        echo ""
        line
        printf "Choose (1-4, or press Enter): "
        IFS= read -r choice
        choice=$(echo "$choice" | tr -d '\r' | xargs)
        
        [ -z "$choice" ] && return
        
        case "$choice" in
            1) settings_directories ;;
            2) settings_categories ;;
            3) settings_default_category ;;
            4) settings_architecture ;;
            *) msg "  Invalid choice" "$RED"; sleep 1 ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# 1. Change Directories
# ------------------------------------------------------------------------------

settings_directories() {
    while true; do
        clear
        msg "===== DIRECTORIES =====" "$CYAN"
        line
        echo ""
        echo "  1. Applications : $APPLICATIONS_DIR"
        echo "  2. Downloads    : $DOWNLOADS_DIR"
        echo "  3. Icons        : $ICONS_DIR"
        echo "  0. Back"
        echo ""
        line
        printf "Select (1-3, 0=Back): "
        IFS= read -r choice
        choice=$(echo "$choice" | tr -d '\r' | xargs)
        
        [ -z "$choice" ] && return
        [ "$choice" = "0" ] && return
        
        case "$choice" in
            1) 
                printf "New Applications path: "
                IFS= read -r new_path
                [ -n "$new_path" ] && { APPLICATIONS_DIR="$new_path"; save_settings; msg "  ✓ Saved" "$GREEN"; sleep 1; }
                ;;
            2) 
                printf "New Downloads path: "
                IFS= read -r new_path
                [ -n "$new_path" ] && { DOWNLOADS_DIR="$new_path"; save_settings; msg "  ✓ Saved" "$GREEN"; sleep 1; }
                ;;
            3) 
                printf "New Icons path: "
                IFS= read -r new_path
                [ -n "$new_path" ] && { ICONS_DIR="$new_path"; save_settings; msg "  ✓ Saved" "$GREEN"; sleep 1; }
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# 2. Category Normalization
# ------------------------------------------------------------------------------

settings_categories() {
    while true; do
        clear
        msg "===== CATEGORY NORMALIZATION =====" "$CYAN"
        line
        echo ""
        msg "  Type 'd' to toggle default" "$YELLOW"
        echo ""
        
        local cats=()
        while IFS= read -r cat; do
            [ -n "$cat" ] && cats+=("$cat")
        done < <(get_main_categories)
        
        for i in "${!cats[@]}"; do
            local default_mark=""
            [ "${cats[$i]}" = "$DEFAULT_MAIN_CATEGORY" ] && default_mark=" ${GREEN}[Default]${NC}"
            local subs=$(get_subcategories "${cats[$i]}")
            [ -z "$subs" ] && subs="none"
            echo -e "  $((i+1)). ${cats[$i]}$default_mark"
            echo "     ↳ $subs"
        done
        
        echo ""
        echo "  0. Back"
        line
        printf "Select category to edit (1-${#cats[@]}, d=toggle default, 0=Back): "
        IFS= read -r choice
        choice=$(echo "$choice" | tr -d '\r' | xargs)
        
        [ -z "$choice" ] && return
        [ "$choice" = "0" ] && return
        
        if [ "$choice" = "d" ]; then
            # Toggle default category
            printf "Set category number as default: "
            IFS= read -r cat_num
            if [ "$cat_num" -ge 1 ] 2>/dev/null && [ "$cat_num" -le ${#cats[@]} ]; then
                DEFAULT_MAIN_CATEGORY="${cats[$((cat_num-1))]}"
                save_settings
                msg "  ✓ Default: $DEFAULT_MAIN_CATEGORY" "$GREEN"
                sleep 1
            fi
            continue
        fi
        
        if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le ${#cats[@]} ]; then
            edit_subcategories "${cats[$((choice-1))]}"
        fi
    done
}

# Edit subcategories for a specific main category
edit_subcategories() {
    local main_cat="$1"
    local subs=$(get_subcategories "$main_cat")
    
    # Convert comma-separated to array
    IFS=',' read -ra sub_arr <<< "$subs"
    
    while true; do
        clear
        local default_mark=""
        [ "$main_cat" = "$DEFAULT_MAIN_CATEGORY" ] && default_mark=" ${GREEN}[Default]${NC}"
        
        echo -e "===== $main_cat$default_mark ====="
        line
        echo ""
        msg "  Numbers toggle on/off, 0=Done" "$YELLOW"
        echo ""
        
        for i in "${!sub_arr[@]}"; do
            echo "  $((i+1)). ${sub_arr[$i]} [✓]"
        done
        
        local next_num=$((${#sub_arr[@]} + 1))
        echo "  $next_num. + Add new"
        echo "  0. Done"
        echo ""
        line
        printf "Select: "
        IFS= read -r choice
        choice=$(echo "$choice" | tr -d '\r' | xargs)
        
        [ "$choice" = "0" ] && break
        
        if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le ${#sub_arr[@]} ]; then
            # Remove this subcategory
            local new_subs=()
            for i in "${!sub_arr[@]}"; do
                [ "$i" -ne "$((choice-1))" ] && new_subs+=("${sub_arr[$i]}")
            done
            sub_arr=("${new_subs[@]}")
        elif [ "$choice" = "$next_num" ]; then
            # Add new
            printf "  New subcategory: "
            IFS= read -r new_sub
            [ -n "$new_sub" ] && sub_arr+=("$new_sub")
        fi
    done
    
    # Save
    local new_subs=$(IFS=','; echo "${sub_arr[*]}")
    set_subcategories "$main_cat" "$new_subs"
}

# ------------------------------------------------------------------------------
# 3. Default Category
# ------------------------------------------------------------------------------

settings_default_category() {
    clear
    msg "===== DEFAULT CATEGORY =====" "$CYAN"
    line
    echo ""
    msg "  Current: $DEFAULT_MAIN_CATEGORY" "$BLUE"
    echo ""
    
    local cats=()
    while IFS= read -r cat; do
        [ -n "$cat" ] && cats+=("$cat")
    done < <(get_main_categories)
    
    for i in "${!cats[@]}"; do
        local mark=""
        [ "${cats[$i]}" = "$DEFAULT_MAIN_CATEGORY" ] && mark=" ${GREEN}[current]${NC}"
        echo "  $((i+1)). ${cats[$i]}$mark"
    done
    
    echo ""
    echo "  0. Back"
    line
    printf "Select new default (1-${#cats[@]}, 0=Back): "
    IFS= read -r choice
    choice=$(echo "$choice" | tr -d '\r' | xargs)
    
    [ -z "$choice" ] && return
    [ "$choice" = "0" ] && return
    
    if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le ${#cats[@]} ]; then
        DEFAULT_MAIN_CATEGORY="${cats[$((choice-1))]}"
        save_settings
        msg "  ✓ Default category: $DEFAULT_MAIN_CATEGORY" "$GREEN"
        pause
    fi
}

# ------------------------------------------------------------------------------
# 4. Set Architecture
# ------------------------------------------------------------------------------

settings_architecture() {
    local system_arch=$(get_system_arch)
    
    while true; do
        clear
        msg "===== DOWNLOAD FILE ARCHITECTURE =====" "$CYAN"
        line
        echo ""
        msg "  Current setting: $ARCHITECTURE" "$BLUE"
        msg "  System architecture: $system_arch" "$GREEN"
        echo ""
        echo "  Select architecture for downloading:"
        echo ""
        echo "  0. Auto (detect from system)  ${GREEN}[Recommended]${NC}"
        echo "  1. x86_64 / amd64"
        echo "  2. ARM64 / aarch64"
        echo "  3. ARMv7"
        echo "  4. ARMv6"
        echo ""
        echo "  M. Main Menu"
        echo "  Enter (empty) = Back"
        line
        printf "Select architecture (0-4, or Enter to exit): "
        IFS= read -r choice
        choice=$(echo "$choice" | tr -d '\r' | xargs)
        
        [ -z "$choice" ] && return
        
        case "$choice" in
            0)
                ARCHITECTURE="auto"
                save_settings
                msg "  ✓ Architecture set to: Auto (detect from system)" "$GREEN"
                pause
                return
                ;;
            1)
                ARCHITECTURE="x86_64"
                save_settings
                msg "  ✓ Architecture set to: x86_64 / amd64" "$GREEN"
                pause
                return
                ;;
            2)
                ARCHITECTURE="aarch64"
                save_settings
                msg "  ✓ Architecture set to: ARM64 / aarch64" "$GREEN"
                pause
                return
                ;;
            3)
                ARCHITECTURE="armv7"
                save_settings
                msg "  ✓ Architecture set to: ARMv7" "$GREEN"
                pause
                return
                ;;
            4)
                ARCHITECTURE="armv6"
                save_settings
                msg "  ✓ Architecture set to: ARMv6" "$GREEN"
                pause
                return
                ;;
            M|m)
                return 0
                ;;
            *)
                msg "  Invalid choice (0-4, M, or Enter)" "$RED"
                sleep 1
                ;;
        esac
    done
}

# ==============================================================================
# INIT - Load settings on startup
# ==============================================================================

load_settings
