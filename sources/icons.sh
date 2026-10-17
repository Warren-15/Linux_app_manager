# ------------------------------------------------------------------------------
# ICONS
# ------------------------------------------------------------------------------

find_icons() {
    find "$1" -maxdepth 1 -type f \
      \( -iname "*.png" -o -iname "*.svg" -o -iname "*.ico" -o -iname "*.xpm" \) \
      2>/dev/null
    find "$1" -mindepth 2 -maxdepth 2 -type f \
      \( -iname "*.png" -o -iname "*.svg" -o -iname "*.ico" -o -iname "*.xpm" \) \
      ! -path "*/templates/*" ! -path "*/Template*" \
      2>/dev/null | head -20
}

# ------------------------------------------------------------------------------
# FIND MATCHING ICON SMARTLY
# ------------------------------------------------------------------------------
find_matching_icon_smart() {
    local app_name="$1"
    local search_dir="$2"
    
    # Clean app name (remove version numbers)
    local clean_app_name=$(echo "$app_name" | sed -E 's/[0-9]+\.[0-9]+(\.[0-9]+)?//g' | sed 's/  / /g' | sed 's/ $//')
    
    # Split app name into words
    local app_words=()
    IFS=' -_' read -ra app_words <<< "$clean_app_name"
    
    # Search directories
    local dirs=("$ICONS_DIR" "$SCRIPT_DIR" "$search_dir")
    
    for dir in "${dirs[@]}"; do
        [ ! -d "$dir" ] && continue
        
        local icons=()
        while IFS= read -r f; do
            [ -n "$f" ] && icons+=("$f")
        done < <(find "$dir" -maxdepth 1 -type f \
            \( -iname "*.png" -o -iname "*.svg" -o -iname "*.ico" -o -iname "*.xpm" \) \
            2>/dev/null)
        
        if [ ${#icons[@]} -eq 0 ]; then
            continue
        fi
        
        local best_match=""
        local best_score=0
        
        for i in "${!icons[@]}"; do
            local icon_name=$(basename "${icons[$i]}" | tr '[:upper:]' '[:lower:]')
            local icon_base="${icon_name%.*}"
            
            local score=0
            for w in "${app_words[@]}"; do
                local lower_w=$(echo "$w" | tr '[:upper:]' '[:lower:]')
                [ ${#lower_w} -lt 3 ] && continue
                
                if [[ "$icon_base" == *"$lower_w"* ]]; then
                    score=$((score + ${#lower_w}))
                fi
                if [[ "$lower_w" == *"$icon_base"* ]] && [ ${#icon_base} -ge 3 ]; then
                    score=$((score + ${#icon_base}))
                fi
            done
            
            if [ $score -gt $best_score ]; then
                best_score=$score
                best_match="${icons[$i]}"
            fi
        done
        
        if [ $best_score -ge 5 ] && [ -n "$best_match" ]; then
            echo "$best_match"
            return
        fi
    done
    
    echo ""
}

# ------------------------------------------------------------------------------
# GET ICON PRIORITY (svg > png > ico > xpm)
# ------------------------------------------------------------------------------

get_icon_priority() {
    local file="$1"
    local lower=$(echo "$file" | tr '[:upper:]' '[:lower:]')
    
    case "$lower" in
        *.svg)   echo 100 ;;
        *.png)   echo 80 ;;
        *.ico)   echo 60 ;;
        *.xpm)   echo 40 ;;
        *)       echo 0 ;;
    esac
}

# ------------------------------------------------------------------------------
# CHECK IF TWO NAMES HAVE A MEANINGFUL COMMON WORD
# ------------------------------------------------------------------------------

has_common_word() {
    local name1="$1"
    local name2="$2"
    
    local clean1=$(echo "$name1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/ /g')
    local clean2=$(echo "$name2" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/ /g')
    
    # Split into words
    read -ra words1 <<< "$clean1"
    read -ra words2 <<< "$clean2"
    
    # Require at least one meaningful common word (>=4 chars)
    for w1 in "${words1[@]}"; do
        [ ${#w1} -lt 4 ] && continue
        
        for w2 in "${words2[@]}"; do
            [ ${#w2} -lt 4 ] && continue
            
            if [ "$w1" = "$w2" ]; then
                return 0
            fi
        done
    done
    
    return 1
}

# ------------------------------------------------------------------------------
# CHECK IF ICON NAME IS GENERIC (SHOULD NOT BE AUTO-SELECTED)
# ------------------------------------------------------------------------------

is_generic_icon() {
    local icon_name="$1"
    local lower=$(echo "$icon_name" | tr '[:upper:]' '[:lower:]')
    
    case "$lower" in
        logo|icon|application|app|default|placeholder|generic|unknown)
            return 0
            ;;
        inkscape*|gimp*|firefox*|vlc*|libreoffice*|krita*|audacity*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# ==============================================================================
# SELECT ICON - SIMPLIFIED
# ==============================================================================

select_icon() {
    local search="$1"
    local app_name="$2"
    local mode="${3:-install}"  # install or edit
    ICON_RESULT=""

    local title="SELECT ICON"
    [ -n "$app_name" ] && title="SELECT ICON - $app_name"

    # ============================================
    # INSTALL MODE: Use icons from program folder only
    # ============================================
    if [ "$mode" = "install" ] && [ -d "$search" ]; then
        local icons=()
        while IFS= read -r f; do
            [ -n "$f" ] && icons+=("$f")
        done < <(find_icons "$search")
        
        if [ ${#icons[@]} -gt 0 ]; then
            # Sort by priority (SVG > PNG > ICO)
            local sorted_icons=()
            local icons_with_priority=()
            
            for icon in "${icons[@]}"; do
                icons_with_priority+=("$icon|$(get_icon_priority "$icon")")
            done
            
            IFS=$'\n' icons_with_priority=($(sort -t'|' -k2 -rn <<<"${icons_with_priority[*]}"))
            unset IFS
            
            for item in "${icons_with_priority[@]}"; do
                sorted_icons+=("${item%|*}")
            done
            
            # Auto-select the highest priority icon
            local selected="${sorted_icons[0]}"
            echo ""
            msg "  ✓ Icon: $(basename "$selected") (auto-selected by priority)" "$GREEN"
            sleep 1
            ICON_RESULT="$selected"
            return
        fi
    fi

    # ============================================
    # EDIT MODE (or no icons in install mode): Match by name or manual selection
    # ============================================
    
    # First, try to auto-match by name from global icons
    local matched_icon=$(auto_select_icon_by_name "$app_name")
    
    if [ -n "$matched_icon" ]; then
        echo ""
        msg "  ✓ Icon: $(basename "$matched_icon") (auto-matched by name)" "$GREEN"
        sleep 1
        ICON_RESULT="$matched_icon"
        return
    fi
    
    # If no match, show manual selection menu
    local all_icons=()
    for icon_dir in "$ICONS_DIR" "$SCRIPT_DIR"; do
        while IFS= read -r f; do
            [ -n "$f" ] && all_icons+=("$f")
        done < <(find_icons "$icon_dir")
    done
    
    if [ ${#all_icons[@]} -gt 0 ]; then
        # Sort by priority for display
        local sorted_icons=()
        local icons_with_priority=()
        
        for icon in "${all_icons[@]}"; do
            icons_with_priority+=("$icon|$(get_icon_priority "$icon")")
        done
        
        IFS=$'\n' icons_with_priority=($(sort -t'|' -k2 -rn <<<"${icons_with_priority[*]}"))
        unset IFS
        
        for item in "${icons_with_priority[@]}"; do
            sorted_icons+=("${item%|*}")
        done
        
        while true; do
            clear
            msg "===== $title =====" "$GREEN"
            line
            msg "  App: $app_name" "$CYAN"
            if [ "$mode" = "install" ]; then
                msg "  No icons in app folder - select from global icons" "$YELLOW"
            else
                msg  "Select from global icons" "$BLUE"
            fi
            line
            local i
            for i in "${!sorted_icons[@]}"; do
                local ext=$(basename "${sorted_icons[$i]}" | tr '[:upper:]' '[:lower:]')
                local priority_indicator=""
                if [[ "$ext" == *.svg ]]; then
                    priority_indicator=" [SVG]"
                elif [[ "$ext" == *.png ]]; then
                    priority_indicator=" [PNG]"
                elif [[ "$ext" == *.ico ]]; then
                    priority_indicator=" [ICO]"
                fi
                echo "  $((i+1)). $(basename "${sorted_icons[$i]}")$priority_indicator"
            done
            echo "  0. Skip"
            line
            echo ""
            printf "Select (0-${#sorted_icons[@]}): "
            read c

            [ "$c" = "0" ] && { ICON_RESULT=""; return; }
            [ -z "$c" ] && { msg "  Enter 0 to skip or 1-${#sorted_icons[@]}" "$RED"; sleep 1; continue; }
            if [ "$c" -ge 1 ] 2>/dev/null && [ "$c" -le ${#sorted_icons[@]} ]; then
                ICON_RESULT="${sorted_icons[$((c-1))]}"
                return
            fi
            msg "  Invalid (0-${#sorted_icons[@]})" "$RED"
            sleep 1
        done
    fi

    echo ""
    msg "  No icons found" "$YELLOW"
    sleep 1
    ICON_RESULT=""
}

# ------------------------------------------------------------------------------
# AUTO-SELECT ICON BY NAME (FOR EDIT MODE)
# ------------------------------------------------------------------------------

auto_select_icon_by_name() {
    local app_name="$1"
    
    # Clean app name
    local clean_name=$(echo "$app_name" | sed -E 's/[0-9]+\.[0-9]+(\.[0-9]+)?//g' | sed 's/  / /g' | sed 's/ $//' | tr '[:upper:]' '[:lower:]')
    local base_name=$(echo "$clean_name" | awk '{print $1}')
    
    # Collect all icons from global locations
    local icons=()
    for icon_dir in "$ICONS_DIR" "$SCRIPT_DIR"; do
        while IFS= read -r f; do
            [ -n "$f" ] && icons+=("$f")
        done < <(find_icons "$icon_dir")
    done
    
    local best_match=""
    local best_score=0
    
    for icon in "${icons[@]}"; do
        local icon_file=$(basename "$icon" | sed 's/\.[^.]*$//' | tr '[:upper:]' '[:lower:]')
        local icon_clean=$(echo "$icon_file" | sed 's/_logo$//' | sed 's/-icon$//' | sed 's/_icon$//')
        
        local score=0
        
        # Exact match
        if [[ "$icon_clean" == "$base_name" ]]; then
            score=100
        # Icon contains app name
        elif [[ "$icon_clean" == *"$base_name"* ]] && [ ${#base_name} -ge 4 ]; then
            score=${#base_name}
        # App name contains icon name
        elif [[ "$base_name" == *"$icon_clean"* ]] && [ ${#icon_clean} -ge 4 ]; then
            score=${#icon_clean}
        fi
        
        if [ $score -gt $best_score ]; then
            best_score=$score
            best_match="$icon"
        fi
    done
    
    # Require at least 4 characters match
    if [ $best_score -ge 4 ] && [ -n "$best_match" ]; then
        echo "$best_match"
        return
    fi
    
    echo ""
}
