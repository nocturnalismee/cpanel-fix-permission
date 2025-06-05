#!/bin/bash
# ==============================================
# cPanel Fix Permission Script
# Version: 0.1
# Author: nocturnalismee
# Description: Script to fix permission and ownership
# of files and folders on cPanel account
# ==============================================

# Constants
readonly SCRIPT_NAME=$(basename "$0")
readonly LOG_FILE="/tmp/cpanel-fix-permission.log"
readonly TIMEOUT_DURATION=300
readonly VALID_USERNAME_PATTERN='^[a-zA-Z0-9_]+$'

# Color for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Function to show message
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

# Function to show help
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

# Function to timeout
timeout_command() {
    local timeout=$1
    local command=$2
    local pid
    
    $command &
    pid=$!
    
    (
        sleep $timeout
        if kill -0 $pid 2>/dev/null; then
            kill $pid 2>/dev/null
            log_message "ERROR" "Command timeout after $timeout seconds"
            exit 1
        fi
    ) &
    
    wait $pid
    return $?
}

# Function to validate path
validate_path() {
    local path=$1
    local base_path=$2
    
    local normalized_path=$(realpath "$path")
    local normalized_base=$(realpath "$base_path")
    
    if [[ "$normalized_path" != "$normalized_base"* ]]; then
        log_message "ERROR" "Path traversal detected"
        return 1
    fi
    
    return 0
}

# Function to show progress
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Function to process one user
process_user() {
    local user=$1
    local HOMEDIR=$(egrep "^${user}:" /etc/passwd | cut -d: -f6)
    
    log_message "INFO" "Processing user: $user"
    
    if ! [[ "$user" =~ $VALID_USERNAME_PATTERN ]]; then
        log_message "ERROR" "Username is not valid: $user"
        return 1
    fi
    
    if ! validate_path "$HOMEDIR" "/home"; then
        log_message "ERROR" "Home directory is not valid for user: $user"
        return 1
    fi
    
    if [ ! -f /var/cpanel/users/$user ]; then
        log_message "ERROR" "File user not found: $user"
        return 1
    elif [ "$HOMEDIR" == "" ]; then
        log_message "ERROR" "Cannot determine home directory for: $user"
        return 1
    fi
    
    # Process change permission
    log_message "INFO" "Setting ownership for user $user"
    timeout_command $TIMEOUT_DURATION "chown -R $user:$user $HOMEDIR"
    chmod 711 $HOMEDIR
    chown $user:nobody $HOMEDIR/public_html $HOMEDIR/.htpasswds
    chown $user:mail $HOMEDIR/etc $HOMEDIR/etc/*/shadow $HOMEDIR/etc/*/passwd
    
    # Process change permission file and directory
    log_message "INFO" "Setting permission for user $user"
    
    echo -n "Setting permission file to 644..."
    timeout_command $TIMEOUT_DURATION "find $HOMEDIR -type f -exec chmod 644 {} \;" & spinner $!
    echo " Done."
    
    echo -n "Setting permission directory to 755..."
    timeout_command $TIMEOUT_DURATION "find $HOMEDIR -type d -exec chmod 755 {} \;" & spinner $!
    echo " Done."
    
    echo -n "Setting permission cgi-bin to 755..."
    timeout_command $TIMEOUT_DURATION "find $HOMEDIR -type d -name cgi-bin -exec chmod 755 {} \;" & spinner $!
    echo " Done."
    
    echo -n "Setting permission script to 755..."
    timeout_command $TIMEOUT_DURATION "find $HOMEDIR -type f \( -name \"*.pl\" -o -name \"*.perl\" \) -exec chmod 755 {} \;" & spinner $!
    echo " Done."
    
    # Process public_html
    log_message "INFO" "Setting permission public_html to 750"
    chmod 750 $HOMEDIR/public_html & spinner $!
    
    # Process cagefs if exists
    if [ -d "$HOMEDIR/.cagefs" ]; then
        log_message "INFO" "Setting permission .cagefs"
        chmod 771 $HOMEDIR/.cagefs & spinner $!
        chmod 700 $HOMEDIR/.cagefs/tmp & spinner $!
        chmod 700 $HOMEDIR/.cagefs/var & spinner $!
        chmod 700 $HOMEDIR/.cagefs/opt/ & spinner $!
    fi
    
    log_message "INFO" "Finished processing user: $user"
    return 0
}

# Main script
main() {
    # Cek root privileges
    if [ "$EUID" -ne 0 ]; then 
        log_message "ERROR" "Script must be run as root"
        exit 1
    fi
    
    # Process argument
    if [ "$#" -lt "1" ]; then
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
            echo "Version: 0.2"
            exit 0
            ;;
        -a|--all)
            log_message "INFO" "Processing all cPanel accounts"
            for user in $(ls -A /var/cpanel/users); do
                process_user "$user"
            done
            exit 0
            ;;
    esac
    
    # Process each user
    for user in "$@"; do
        process_user "$user"
    done
}

# Trap for error handling
trap 'log_message "ERROR" "Error on line $LINENO"' ERR

# Run main function
main "$@"
