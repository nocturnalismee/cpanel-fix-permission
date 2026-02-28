#!/bin/bash
# ==============================================
# cPanel Fix Permission Script
# Version: 0.3 (Optimized & Patched)
# Author: nocturnalismee (Updated via Analysis)
# Script to fix permission and ownership of files and folders on cPanel account
# Including subdomain and addon domains
# ==============================================

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

readonly SCRIPT_NAME=$(basename "$0")
readonly LOG_FILE="cpanel-fix-permission.log"
readonly TIMEOUT_DURATION=600
readonly VALID_USERNAME_PATTERN='^[a-zA-Z0-9_-]+$'
readonly CPANEL_USER_DIR="/var/cpanel/users"
readonly CPANEL_USERDATA_DIR="/var/cpanel/userdata"

# Color
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

# Show message
log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO") echo -e "${GREEN}[INFO]${NC} $message" ;;
        "WARN") echo -e "${YELLOW}[WARN]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Show Help
show_help() {
    echo "Usage: $SCRIPT_NAME [option] username1 [username2 ...]"
    echo
    echo "Option:"
    echo "  -h, --help     Show this help message"
    echo "  -v, --version  Show version of script"
    echo "  -a, --all      Fix all cPanel accounts"
    echo
    echo "Example:"
    echo "  $SCRIPT_NAME usernameA              # Fix 1 cPanel account"
    echo "  $SCRIPT_NAME usernameA usernameB    # Fix several cPanel accounts"
    echo "  $SCRIPT_NAME -a                     # Fix all cPanel accounts"
    echo
    echo "Log file: $LOG_FILE"
}

# Run command with spinner and capture proper exit code
run_with_spinner() {
    local msg="$1"
    shift
    
    echo -n "  $msg... "
    
    # Run command in background
    "$@" >/dev/null 2>&1 &
    local pid=$!
    
    # Run spinner
    local delay=0.1
    local spinstr='|/-\'
    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?}
        printf "[%c]" "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b"
    done
    
    # Wait for the background process to finish and get its exit code
    wait "$pid"
    local exit_status=$?
    
    # Clear spinner and print result
    if [ $exit_status -eq 0 ]; then
        echo -e " \b\b${GREEN}Done.${NC}"
        return 0
    elif [ $exit_status -eq 124 ]; then
        echo -e " \b\b${RED}Timeout.${NC}"
        return 124
    else
        echo -e " \b\b${RED}Failed.${NC}"
        return $exit_status
    fi
}

# Validate path to prevent directory traversal
validate_path() {
    local path=$1
    local base_path=$2
    
    if [ ! -e "$path" ]; then return 1; fi
    
    local normalized_path
    local normalized_base
    normalized_path=$(realpath "$path" 2>/dev/null) || return 1
    normalized_base=$(realpath "$base_path" 2>/dev/null) || return 1
    
    if [[ "$normalized_path" != "$normalized_base"* ]]; then
        log_message "ERROR" "Path traversal detected: $path not within $base_path"
        return 1
    fi
    
    # Prevent dangerous root system paths
    case "$normalized_path" in
        /|/bin|/boot|/dev|/etc|/lib|/lib64|/proc|/root|/run|/sbin|/sys|/usr|/var/cpanel|/var/named)
            log_message "ERROR" "Dangerous system path detected: $normalized_path"
            return 1
            ;;
    esac
    
    return 0
}

# Get subdomain and addon domain directories
get_additional_domains() {
    local user=$1
    local userdata_dir="$CPANEL_USERDATA_DIR/$user"
    local domains=()
    
    if [ ! -d "$userdata_dir" ]; then return 0; fi
    
    while IFS= read -r -d '' config_file; do
        local basename_file
        basename_file=$(basename "$config_file")
        
        if [[ "$basename_file" == "main" ]] || [[ "$basename_file" == *"cache"* ]]; then
            continue
        fi
        
        if [ -f "$config_file" ]; then
            local docroot
            docroot=$(grep "^documentroot:" "$config_file" 2>/dev/null | head -n1 | cut -d: -f2- | tr -d ' ')
            
            if [ -n "$docroot" ] &&[ -d "$docroot" ]; then
                domains+=("$docroot")
            fi
        fi
    done < <(find "$userdata_dir" -maxdepth 1 -type f -print0 2>/dev/null)
    
    if [ ${#domains[@]} -gt 0 ]; then
        printf '%s\n' "${domains[@]}" | sort -u
    fi
}

# Process subdomain and addon domains
process_additional_domains() {
    local user=$1
    local HOMEDIR=$2
    local BASE_HOMEDIR=$(dirname "$HOMEDIR")
    
    log_message "INFO" "Checking for subdomains and addon domains for user: $user"
    
    local additional_domains
    additional_domains=$(get_additional_domains "$user")
    
    if[ -z "$additional_domains" ]; then return 0; fi
    
    while IFS= read -r domain_path; do
        [ -z "$domain_path" ] && continue
        
        if[ -d "$domain_path" ]; then
            log_message "INFO" "Processing domain directory: $domain_path"
            
            if validate_path "$domain_path" "$BASE_HOMEDIR"; then
                
                chown -R "$user:$user" "$domain_path" 2>/dev/null || log_message "WARN" "Failed setting ownership on $domain_path"
                
                if ! run_with_spinner "Setting file permissions in $(basename "$domain_path")" timeout "$TIMEOUT_DURATION" find "$domain_path" -type f -exec chmod 644 {} +; then
                    log_message "WARN" "Some file permissions may not be set in: $domain_path"
                fi
                
                if ! run_with_spinner "Setting dir permissions in $(basename "$domain_path")" timeout "$TIMEOUT_DURATION" find "$domain_path" -type d -exec chmod 755 {} +; then
                    log_message "WARN" "Some directory permissions may not be set in: $domain_path"
                fi
                
                # Setup specific root ownership & permission for domain
                chmod 750 "$domain_path" 2>/dev/null
                chown "$user:nobody" "$domain_path" 2>/dev/null
                
            else
                log_message "WARN" "Skipping invalid path: $domain_path"
            fi
        fi
    done <<< "$additional_domains"
}

# Process one user
process_user() {
    local user=$1
    local HOMEDIR
    
    log_message "INFO" "Processing user: $user"
    
    if ! [[ "$user" =~ $VALID_USERNAME_PATTERN ]]; then
        log_message "ERROR" "Username is not valid: $user"
        return 1
    fi
    
    if [ ! -f "$CPANEL_USER_DIR/$user" ]; then
        log_message "ERROR" "cPanel user not found: $user"
        return 1
    fi
    
    HOMEDIR=$(grep "^${user}:" /etc/passwd 2>/dev/null | cut -d: -f6)
    
    if [ -z "$HOMEDIR" ] ||[ ! -d "$HOMEDIR" ]; then
        log_message "ERROR" "Home directory invalid or missing for: $user"
        return 1
    fi
    
    local BASE_HOMEDIR=$(dirname "$HOMEDIR")
    if ! validate_path "$HOMEDIR" "$BASE_HOMEDIR"; then
        log_message "ERROR" "Home directory structure is restricted for user: $user"
        return 1
    fi
    
    # 1. Main Ownership Change
    log_message "INFO" "Setting Base Ownership for $user"
    timeout "$TIMEOUT_DURATION" chown -R "$user:$user" "$HOMEDIR" 2>/dev/null || log_message "WARN" "Complete chown took too long or had permission blocks"
    
    chmod 711 "$HOMEDIR" 2>/dev/null
    
    # 2. Fix Mail, SSL, and Specific System Dirs that require different groups
    log_message "INFO" "Restoring specific cPanel directories ownership"
    [ -d "$HOMEDIR/public_html" ] && chown "$user:nobody" "$HOMEDIR/public_html" 2>/dev/null[ -d "$HOMEDIR/public_ftp" ]  && chown "$user:nobody" "$HOMEDIR/public_ftp" 2>/dev/null
    [ -d "$HOMEDIR/.htpasswds" ]  && chown -R "$user:nobody" "$HOMEDIR/.htpasswds" 2>/dev/null && chmod 750 "$HOMEDIR/.htpasswds" 2>/dev/null
    
    # Ensure Mail directories are assigned to mail group to prevent Webmail breakdown
    if[ -d "$HOMEDIR/mail" ]; then
        chown -R "$user:mail" "$HOMEDIR/mail" 2>/dev/null || true
    fi
    if[ -d "$HOMEDIR/etc" ]; then
        chown -R "$user:mail" "$HOMEDIR/etc" 2>/dev/null || true
    fi
    
    # 3. Base Permissions files & dirs
    log_message "INFO" "Setting Base Permissions for $user"
    
    run_with_spinner "Setting files to 644" timeout "$TIMEOUT_DURATION" find "$HOMEDIR" -type f -exec chmod 644 {} + || true
    run_with_spinner "Setting directories to 755" timeout "$TIMEOUT_DURATION" find "$HOMEDIR" -type d -exec chmod 755 {} + || true
    run_with_spinner "Setting cgi-bin to 755" timeout "$TIMEOUT_DURATION" find "$HOMEDIR" -type d -name "cgi-bin" -exec chmod 755 {} + || true
    run_with_spinner "Setting executable scripts to 755" timeout "$TIMEOUT_DURATION" find "$HOMEDIR" -type f \( -name "*.pl" -o -name "*.perl" -o -name "*.cgi" -o -name "*.sh" \) -exec chmod 755 {} + || true
    
    # Restore public_html to 750 (Must be done AFTER the bulk find command above)
    if [ -d "$HOMEDIR/public_html" ]; then
        chmod 750 "$HOMEDIR/public_html" 2>/dev/null
    fi
    
    # 4. Additional Domains
    process_additional_domains "$user" "$HOMEDIR"
    
    # 5. CageFS specific fixes
    if [ -d "$HOMEDIR/.cagefs" ]; then
        log_message "INFO" "Applying .cagefs permissions"
        chmod 771 "$HOMEDIR/.cagefs" 2>/dev/null
        [ -d "$HOMEDIR/.cagefs/tmp" ] && chmod 700 "$HOMEDIR/.cagefs/tmp" 2>/dev/null[ -d "$HOMEDIR/.cagefs/var" ] && chmod 700 "$HOMEDIR/.cagefs/var" 2>/dev/null[ -d "$HOMEDIR/.cagefs/opt" ] && chmod 700 "$HOMEDIR/.cagefs/opt" 2>/dev/null
    fi
    
    log_message "INFO" "Finished processing user: $user"
    echo "---------------------------------------------------"
    return 0
}

# Main script
main() {
    if[ "$EUID" -ne 0 ]; then 
        log_message "ERROR" "Script must be run as root"
        exit 1
    fi
    
    if[ ! -d "$CPANEL_USER_DIR" ]; then
        log_message "ERROR" "cPanel installation not found."
        exit 1
    fi
    
    # Ensure timeout command exists
    if ! command -v timeout >/dev/null 2>&1; then
        log_message "ERROR" "'timeout' command is required but not installed."
        exit 1
    fi
    
    if [ "$#" -lt 1 ]; then
        show_help
        exit 1
    fi
    
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--version)
            echo "Version: 0.3 (Optimized)"
            exit 0
            ;;
        -a|--all)
            log_message "INFO" "Processing all cPanel accounts"
            local user_count=0
            local success_count=0
            local fail_count=0
            
            while IFS= read -r -d '' user_file; do
                local user
                user=$(basename "$user_file")
                ((user_count++))
                
                if process_user "$user"; then
                    ((success_count++))
                else
                    ((fail_count++))
                fi
            done < <(find "$CPANEL_USER_DIR" -maxdepth 1 -type f -print0 2>/dev/null)
            
            log_message "INFO" "Processed $user_count users: $success_count successful, $fail_count failed"
            exit 0
            ;;
    esac
    
    local total_users=$#
    local success_count=0
    local fail_count=0
    
    for user in "$@"; do
        if process_user "$user"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
    done
    
    log_message "INFO" "Processed $total_users users: $success_count successful, $fail_count failed"
}

# Trap for clean error handling
trap 'log_message "ERROR" "Script interrupted or error on line $LINENO"' ERR INT TERM

main "$@"
