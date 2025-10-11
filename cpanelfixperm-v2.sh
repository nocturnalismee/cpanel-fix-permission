#!/bin/bash
# ==============================================
# cPanel Fix Permission Script
# Version: 0.2
# Author: nocturnalismee
# Script to fix permission and ownership of files and folders on cPanel account
# Including subdomain and addon domains
# ==============================================

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

readonly SCRIPT_NAME=$(basename "$0")
readonly LOG_FILE="cpanel-fix-permission.log"
readonly TIMEOUT_DURATION=300
readonly VALID_USERNAME_PATTERN='^[a-zA-Z0-9_-]+$'
readonly CPANEL_USER_DIR="/var/cpanel/users"
readonly CPANEL_USERDATA_DIR="/var/cpanel/userdata"

# Color
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Show message
log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
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

# Set timeout
timeout_command() {
    local timeout=$1
    shift
    
    # Use timeout command if available (safer)
    if command -v timeout >/dev/null 2>&1; then
        timeout "$timeout" "$@"
        return $?
    fi
    
    # Fallback to manual timeout
    "$@" &
    local pid=$!
    local monitor_pid
    (
        sleep "$timeout"
        if kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid" 2>/dev/null
            sleep 2
            if kill -0 "$pid" 2>/dev/null; then
                kill -KILL "$pid" 2>/dev/null
            fi
            log_message "ERROR" "Command timeout after $timeout seconds"
            exit 124
        fi
    ) &
    monitor_pid=$!
    wait "$pid"
    local exit_code=$?
    kill "$monitor_pid" 2>/dev/null || true
    return $exit_code
}

# Validate path
validate_path() {
    local path=$1
    local base_path=$2
    
    # Check if path exists
    if [ ! -e "$path" ]; then
        log_message "ERROR" "Path does not exist: $path"
        return 1
    fi
    
    # Get real paths
    local normalized_path
    local normalized_base
    normalized_path=$(realpath "$path" 2>/dev/null) || return 1
    normalized_base=$(realpath "$base_path" 2>/dev/null) || return 1
    
    # Check if path is within base path
    if [[ "$normalized_path" != "$normalized_base"* ]]; then
        log_message "ERROR" "Path traversal detected: $path not within $base_path"
        return 1
    fi
    
    # Prevent dangerous paths
    case "$normalized_path" in
        /|/bin|/boot|/dev|/etc|/lib|/lib64|/proc|/root|/run|/sbin|/sys|/usr|/var/cpanel|/var/named)
            log_message "ERROR" "Dangerous system path detected: $normalized_path"
            return 1
            ;;
    esac
    
    return 0
}

# Show progress
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Get subdomain and addon domain directories
get_additional_domains() {
    local user=$1
    local userdata_dir="$CPANEL_USERDATA_DIR/$user"
    local domains=()
    
    if [ ! -d "$userdata_dir" ]; then
        return 0
    fi
    
    # Parse all domain config files
    while IFS= read -r -d '' config_file; do
        local basename_file
        basename_file=$(basename "$config_file")
        
        # Skip main config and cache files
        if [[ "$basename_file" == "main" ]] || [[ "$basename_file" == "cache" ]] || [[ "$basename_file" == "*.cache" ]]; then
            continue
        fi
        
        # Extract documentroot from config - safer parsing
        if [ -f "$config_file" ]; then
            local docroot
            docroot=$(grep "^documentroot:" "$config_file" 2>/dev/null | head -n1 | cut -d: -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            
            if [ -n "$docroot" ] && [ -d "$docroot" ]; then
                domains+=("$docroot")
            fi
        fi
    done < <(find "$userdata_dir" -maxdepth 1 -type f -print0 2>/dev/null)
    
    # Return unique directories
    if [ ${#domains[@]} -gt 0 ]; then
        printf '%s\n' "${domains[@]}" | sort -u
    fi
}

# Process subdomain and addon domains
process_additional_domains() {
    local user=$1
    local HOMEDIR=$2
    
    log_message "INFO" "Checking for subdomains and addon domains for user: $user"
    
    local additional_domains
    additional_domains=$(get_additional_domains "$user")
    
    if [ -z "$additional_domains" ]; then
        log_message "INFO" "No additional domains found for user: $user"
        return 0
    fi
    
    while IFS= read -r domain_path; do
        # Skip empty lines
        [ -z "$domain_path" ] && continue
        
        if [ -d "$domain_path" ]; then
            log_message "INFO" "Processing domain directory: $domain_path"
            
            # Validate path is within user's home directory
            if validate_path "$domain_path" "$HOMEDIR"; then
                echo -n "  Setting ownership for $domain_path..."
                if chown -R "$user:$user" "$domain_path" 2>/dev/null; then
                    echo " Done."
                else
                    echo " Failed."
                    log_message "ERROR" "Failed to set ownership for: $domain_path"
                    continue
                fi
                
                echo -n "  Setting permissions for files in $domain_path..."
                if timeout_command "$TIMEOUT_DURATION" find "$domain_path" -type f -exec chmod 644 {} + 2>/dev/null & spinner $!; then
                    echo " Done."
                else
                    echo " Failed."
                    log_message "WARN" "Some file permissions may not be set in: $domain_path"
                fi
                
                echo -n "  Setting permissions for directories in $domain_path..."
                if timeout_command "$TIMEOUT_DURATION" find "$domain_path" -type d -exec chmod 755 {} + 2>/dev/null & spinner $!; then
                    echo " Done."
                else
                    echo " Failed."
                    log_message "WARN" "Some directory permissions may not be set in: $domain_path"
                fi
                
                # Set main directory permission
                chmod 750 "$domain_path" 2>/dev/null || log_message "WARN" "Could not set 750 on $domain_path"
                chown "$user:nobody" "$domain_path" 2>/dev/null || log_message "WARN" "Could not set nobody group on $domain_path"
                
                log_message "INFO" "Finished processing: $domain_path"
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
    
    # Validate username
    if ! [[ "$user" =~ $VALID_USERNAME_PATTERN ]]; then
        log_message "ERROR" "Username is not valid: $user"
        return 1
    fi
    
    # Check if user exists in cPanel
    if [ ! -f "$CPANEL_USER_DIR/$user" ]; then
        log_message "ERROR" "cPanel user not found: $user"
        return 1
    fi
    
    # Get home directory safely
    HOMEDIR=$(grep "^${user}:" /etc/passwd 2>/dev/null | cut -d: -f6)
    
    if [ -z "$HOMEDIR" ]; then
        log_message "ERROR" "Cannot determine home directory for: $user"
        return 1
    fi
    
    # Validate home directory
    if [ ! -d "$HOMEDIR" ]; then
        log_message "ERROR" "Home directory does not exist: $HOMEDIR"
        return 1
    fi
    
    if ! validate_path "$HOMEDIR" "/home"; then
        log_message "ERROR" "Home directory is not valid for user: $user"
        return 1
    fi
    
    # Change ownership
    log_message "INFO" "Setting ownership for user $user"
    if ! timeout_command "$TIMEOUT_DURATION" chown -R "$user:$user" "$HOMEDIR" 2>/dev/null; then
        log_message "ERROR" "Failed to set ownership for: $HOMEDIR"
        return 1
    fi
    
    chmod 711 "$HOMEDIR" 2>/dev/null || log_message "WARN" "Could not set 711 on $HOMEDIR"
    
    # Set specific directory ownership
    [ -d "$HOMEDIR/public_html" ] && chown "$user:nobody" "$HOMEDIR/public_html" 2>/dev/null
    [ -d "$HOMEDIR/.htpasswds" ] && chown "$user:nobody" "$HOMEDIR/.htpasswds" 2>/dev/null
    [ -d "$HOMEDIR/etc" ] && chown "$user:mail" "$HOMEDIR/etc" 2>/dev/null
    
    # Set mail directory permissions
    if [ -d "$HOMEDIR/etc" ]; then
        find "$HOMEDIR/etc" -type f -name "shadow" -exec chown "$user:mail" {} + 2>/dev/null || true
        find "$HOMEDIR/etc" -type f -name "passwd" -exec chown "$user:mail" {} + 2>/dev/null || true
    fi
    
    # Process change permission file and directory
    log_message "INFO" "Setting permissions for user $user"
    
    echo -n "Setting permission files to 644..."
    if timeout_command "$TIMEOUT_DURATION" find "$HOMEDIR" -type f -exec chmod 644 {} + 2>/dev/null & spinner $!; then
        echo " Done."
    else
        echo " Failed."
        log_message "WARN" "Some file permissions may not be set"
    fi
    
    echo -n "Setting permission directories to 755..."
    if timeout_command "$TIMEOUT_DURATION" find "$HOMEDIR" -type d -exec chmod 755 {} + 2>/dev/null & spinner $!; then
        echo " Done."
    else
        echo " Failed."
        log_message "WARN" "Some directory permissions may not be set"
    fi
    
    echo -n "Setting permission cgi-bin to 755..."
    if timeout_command "$TIMEOUT_DURATION" find "$HOMEDIR" -type d -name "cgi-bin" -exec chmod 755 {} + 2>/dev/null & spinner $!; then
        echo " Done."
    else
        echo " Failed."
    fi
    
    echo -n "Setting permission scripts to 755..."
    if timeout_command "$TIMEOUT_DURATION" find "$HOMEDIR" -type f \( -name "*.pl" -o -name "*.perl" -o -name "*.cgi" -o -name "*.sh" \) -exec chmod 755 {} + 2>/dev/null & spinner $!; then
        echo " Done."
    else
        echo " Failed."
    fi
    
    # Process public_html
    if [ -d "$HOMEDIR/public_html" ]; then
        log_message "INFO" "Setting permission public_html to 750"
        chmod 750 "$HOMEDIR/public_html" 2>/dev/null & spinner $!
    fi
    
    # Process subdomain and addon domains
    process_additional_domains "$user" "$HOMEDIR"
    
    # Process cagefs if exists
    if [ -d "$HOMEDIR/.cagefs" ]; then
        log_message "INFO" "Setting permission .cagefs"
        chmod 771 "$HOMEDIR/.cagefs" 2>/dev/null & spinner $!
        [ -d "$HOMEDIR/.cagefs/tmp" ] && chmod 700 "$HOMEDIR/.cagefs/tmp" 2>/dev/null & spinner $!
        [ -d "$HOMEDIR/.cagefs/var" ] && chmod 700 "$HOMEDIR/.cagefs/var" 2>/dev/null & spinner $!
        [ -d "$HOMEDIR/.cagefs/opt" ] && chmod 700 "$HOMEDIR/.cagefs/opt" 2>/dev/null & spinner $!
    fi
    
    log_message "INFO" "Finished processing user: $user"
    return 0
}

# Main script
main() {
    # Check root privileges
    if [ "$EUID" -ne 0 ]; then 
        log_message "ERROR" "Script must be run as root"
        exit 1
    fi
    
    # Verify cPanel installation
    if [ ! -d "$CPANEL_USER_DIR" ]; then
        log_message "ERROR" "cPanel installation not found. Is this a cPanel server?"
        exit 1
    fi
    
    # Process argument
    if [ "$#" -lt 1 ]; then
        show_help
        exit 1
    fi
    
    # Check option
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--version)
            echo "Version: 0.4"
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
    
    # Process each user from arguments
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

# Run main function
main "$@"
