# ------------------------------------------------------------------------------
# COLORS
# ------------------------------------------------------------------------------

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m'

msg() { echo -e "${2}${1}${NC}"; }

pause() {
    echo ""
    printf "Press Enter to continue..."
    read dummy
}

line() {
    echo "══════════════════════════════════════════════════"
}

# ------------------------------------------------------------------------------
# MENU HELPER
# ------------------------------------------------------------------------------

# Show menu with standardized behavior
# Returns: 0 for Main Menu, 255 for Back, 1-N for selected option
show_menu() {
    local title="$1"
    shift
    local options=("$@")
    
    while true; do
        clear
        msg "===== $title =====" "$CYAN"
        line
        echo ""
        msg "  ↳ Enter (empty) = Back" "$YELLOW"
        echo ""
        
        local i
        for i in "${!options[@]}"; do
            echo "  $((i+1)). ${options[$i]}"
        done
        
        echo ""
        echo "  M. Main Menu"
        line
        echo ""
        printf "Choose (1-${#options[@]}, M, or press Enter): "
        
        read input
        
        # Empty input = Back
        if [ -z "$input" ]; then
            return 255
        fi
        
        # Main Menu option
        if [ "$input" = "M" ] || [ "$input" = "m" ]; then
            return 0
        fi
        
        # Valid option
        if [ "$input" -ge 1 ] 2>/dev/null && [ "$input" -le ${#options[@]} ]; then
            return $input
        fi
        
        msg "  Invalid choice (1-${#options[@]}, M, or Enter)" "$RED"
        sleep 1
    done
}

# Confirm action with Yes/No
confirm_action() {
    local message="$1"
    local default="${2:-2}"
    
    echo ""
    msg "  $message" "$YELLOW"
    echo "  1. Yes"
    echo "  2. No"
    printf "  Choose (1-2) [default: $default]: "
    read input
    
    [ -z "$input" ] && input="$default"
    [ "$input" = "1" ] && return 0
    return 1
}
