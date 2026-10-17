
# ==============================================================================
# REMOVE MENU - with cancel support
# ==============================================================================

menu_remove() {
    local dirs=()
    for d in "$APPLICATIONS_DIR"/*/; do
        [ -d "$d" ] || continue
        dirs+=("$(basename "$d")")
    done

    [ "${#dirs[@]}" -eq 0 ] && { msg "No applications in $APPLICATIONS_DIR" "$YELLOW"; pause; return; }

    local selected=()
    while true; do
        clear
        msg "===== REMOVE (Queue) =====" "$RED"
        msg "Selected: ${#selected[@]} item(s)" "$YELLOW"
        echo ""
        msg "  ↳ Enter (empty) = Confirm & Remove" "$YELLOW"
        echo ""

        for i in "${!dirs[@]}"; do
            local marker=""
            for s in "${selected[@]}"; do [ "$s" = "$i" ] && marker=" ${RED}[✓]${NC}"; done
            local has_desk="✗"
            [ -f "$DESKTOP_DIR/${dirs[$i]}.desktop" ] && has_desk="✓"
            echo -e "  $((i+1)). ${dirs[$i]} [$has_desk]$marker"
        done

        echo ""
        echo "  M. Main Menu"
        echo "  Commands: Numbers (1 3 5), 0=all, c=clear"
        line
        printf "> "
        read input

        [ -z "$input" ] && { [ ${#selected[@]} -gt 0 ] && break || return; }
        [ "$input" = "M" ] || [ "$input" = "m" ] && return 0
        [ "$input" = "c" ] && { selected=(); continue; }

        [ "$input" = "0" ] && {
            [ ${#selected[@]} -eq ${#dirs[@]} ] && selected=() || { selected=(); for i in "${!dirs[@]}"; do selected+=("$i"); done; }
            continue
        }

        for num in $input; do
            if [ "$num" -ge 1 ] 2>/dev/null && [ "$num" -le ${#dirs[@]} ]; then
                local idx=$((num-1)) found=0 new_sel=()
                for s in "${selected[@]}"; do [ "$s" = "$idx" ] && found=1 || new_sel+=("$s"); done
                [ $found -eq 0 ] && new_sel+=("$idx")
                selected=("${new_sel[@]}")
            fi
        done
    done

    [ ${#selected[@]} -eq 0 ] && { msg "No items selected" "$YELLOW"; pause; return; }

    clear
    msg "===== REMOVING ${#selected[@]} APP(S) =====" "$RED"
    echo ""

    local remove_all=0
    for idx in "${selected[@]}"; do
        local name="${dirs[$idx]}"
        local path="$APPLICATIONS_DIR/$name"
        local desktop="$DESKTOP_DIR/${name}.desktop"

        local choice=""
        if [ $remove_all -eq 0 ]; then
            echo ""
            msg "  Remove: $name?" "$RED"
            echo "  1. Yes, remove it"
            echo "  2. Yes, remove ALL (don't ask again)"
            echo "  3. No, keep it"
            echo "  4. Cancel ALL"
            printf "  Select: "
            IFS= read -r choice
            choice=$(echo "$choice" | tr -d '\r' | xargs)
        else
            choice="1"  # Auto-remove
            msg "  Auto-removing: $name" "$YELLOW"
        fi

        case $choice in
            4) msg "  ✗ Cancelled ALL" "$RED"; break ;;
            3) msg "  ⤏ Kept $name" "$YELLOW"; continue ;;
            2)
                remove_all=1
                ;&  # Fall through to remove
            1)
                [ -f "$desktop" ] && rm -f "$desktop"
                [ -d "$path" ] && rm -rf "$path"
                msg "  ✓ Removed $name" "$GREEN"
                ;;
        esac
    done
    update_db
    msg "✅ Done!" "$GREEN"
    pause
}

# ------------------------------------------------------------------------------
# REMOVE SUBMENU
# ------------------------------------------------------------------------------

remove_submenu() {
    while true; do
        local options=("Remove Apps" "Remove Categories (custom only)" "Remove Shortcuts")

        show_menu "REMOVE" "${options[@]}"
        local choice=$?

        case $choice in
            0) return ;;
            255) return ;;
            1) menu_remove ;;
            2) menu_remove_category ;;   # This calls the one in categories.sh
            3) menu_remove_shortcuts ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Remove empty custom categories (automatic)
# ------------------------------------------------------------------------------

remove_empty_custom_categories() {
    clear
    msg "===== REMOVE EMPTY CUSTOM CATEGORIES =====" "$RED"
    line

    load_custom_categories

    local empty_cats=()
    for i in "${!CUSTOM_NAMES[@]}"; do
        if is_custom_category_empty "${CUSTOM_INTERNAL[$i]}"; then
            empty_cats+=("${CUSTOM_NAMES[$i]}")
        fi
    done

    if [ ${#empty_cats[@]} -eq 0 ]; then
        msg "  No empty custom categories found" "$GREEN"
        pause
        return
    fi

    msg "  Found ${#empty_cats[@]} empty category(ies):" "$YELLOW"
    echo ""
    for cat in "${empty_cats[@]}"; do
        echo "  - $cat"
    done
    echo ""
    echo "  1. Remove all"
    echo "  2. Cancel"
    printf "  Select: "
    read c

    if [ "$c" = "1" ]; then
        for cat in "${empty_cats[@]}"; do
            remove_custom_category "$cat"
        done
        msg "  ✅ Removed ${#empty_cats[@]} empty category(ies)" "$GREEN"
    fi

    pause
}

# ------------------------------------------------------------------------------
# Remove custom categories (manual queue)
# ------------------------------------------------------------------------------

remove_custom_categories_manual() {
    load_custom_categories

    if [ ${#CUSTOM_NAMES[@]} -eq 0 ]; then
        msg "  No custom categories found" "$YELLOW"
        pause
        return
    fi

    local selected=()
    while true; do
        clear
        msg "===== REMOVE CUSTOM CATEGORIES =====" "$RED"
        msg "Selected: ${#selected[@]}" "$YELLOW"
        echo ""

        for i in "${!CUSTOM_NAMES[@]}"; do
            local marker=""
            for s in "${selected[@]}"; do [ "$s" = "$i" ] && marker=" ${RED}[✓]${NC}"; done
            local empty=""
            is_custom_category_empty "${CUSTOM_INTERNAL[$i]}" && empty=" ${YELLOW}[empty]${NC}"
            echo -e "  $((i+1)). ${CUSTOM_NAMES[$i]}$empty$marker"
        done

        echo ""
        echo "  Numbers (1 3 5), 0=all, Enter=confirm, c=clear"
        printf "> "
        read input

        [ -z "$input" ] && break
        [ "$input" = "c" ] && { selected=(); continue; }
        [ "$input" = "0" ] && {
            [ ${#selected[@]} -eq ${#CUSTOM_NAMES[@]} ] && selected=() || selected=($(seq 0 $((${#CUSTOM_NAMES[@]}-1))))
            continue
        }
        for num in $input; do
            if [ "$num" -ge 1 ] 2>/dev/null && [ "$num" -le ${#CUSTOM_NAMES[@]} ]; then
                local idx=$((num-1)) found=0 new_sel=()
                for s in "${selected[@]}"; do [ "$s" = "$idx" ] && found=1 || new_sel+=("$s"); done
                [ $found -eq 0 ] && new_sel+=("$idx")
                selected=("${new_sel[@]}")
            fi
        done
    done

    [ ${#selected[@]} -eq 0 ] && return

    clear
    msg "Removing ${#selected[@]} category(ies)..." "$RED"
    echo ""

    for idx in "${selected[@]}"; do
        remove_custom_category "${CUSTOM_NAMES[$idx]}"
    done

    msg "✅ Done!" "$GREEN"
    pause
}

# ------------------------------------------------------------------------------
# REMOVE CATEGORY MAIN MENU
# ------------------------------------------------------------------------------

menu_remove_category() {
    while true; do
        clear
        msg "===== REMOVE CUSTOM CATEGORIES =====" "$CYAN"
        line
        echo ""
        msg "  ↳ Enter (empty) = Back" "$YELLOW"
        echo ""
        echo "  1. Automatic (remove all empty custom categories)"
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
            1) remove_empty_custom_categories ;;
            2) remove_custom_categories_manual ;;
            *) msg "  Invalid choice (1-2, M, or Enter)" "$RED"; sleep 1 ;;
        esac
    done
}
