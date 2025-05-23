#!/bin/bash
# cPanel Fix Permission Script
# Copyright (C) 2025
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

# ==============================================
# cPanel Fix Permission Script
# Version: 0.1
# Author: nocturnalismee
# Description: Script to fix permission and ownership
# of files and folders on cPanel account
# ==============================================

# Konstanta
readonly SCRIPT_NAME=$(basename "$0")
readonly LOG_FILE="/etc/tmp/cpanel-fix-permission.log"
readonly TIMEOUT_DURATION=300
readonly VALID_USERNAME_PATTERN='^[a-zA-Z0-9_]+$'

# Warna untuk output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Fungsi untuk menampilkan pesan
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

# Fungsi untuk menampilkan bantuan
show_help() {
    echo "Penggunaan: $SCRIPT_NAME [opsi] username1 [username2 ...]"
    echo
    echo "Opsi:"
    echo "  -h, --help     Menampilkan bantuan ini"
    echo "  -v, --version  Menampilkan versi script"
    echo
    echo "Contoh penggunaan:"
    echo "  $SCRIPT_NAME usernameA              # Perbaiki 1 akun cPanel"
    echo "  $SCRIPT_NAME usernameA usernameB    # Perbaiki beberapa akun cPanel"
    echo "  for i in \`ls -A /var/cpanel/users\` ; do $SCRIPT_NAME \$i ; done  # Perbaiki semua akun"
    echo
    echo "Log file: $LOG_FILE"
}

# Fungsi untuk timeout
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
            log_message "ERROR" "Command timeout setelah $timeout detik"
            exit 1
        fi
    ) &
    
    wait $pid
    return $?
}

# Fungsi untuk validasi path
validate_path() {
    local path=$1
    local base_path=$2
    
    local normalized_path=$(realpath "$path")
    local normalized_base=$(realpath "$base_path")
    
    if [[ "$normalized_path" != "$normalized_base"* ]]; then
        log_message "ERROR" "Path traversal terdeteksi"
        return 1
    fi
    
    return 0
}

# Fungsi untuk menampilkan progress
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

# Fungsi untuk memproses satu user
process_user() {
    local user=$1
    local HOMEDIR=$(egrep "^${user}:" /etc/passwd | cut -d: -f6)
    
    log_message "INFO" "Memproses user: $user"
    
    if ! [[ "$user" =~ $VALID_USERNAME_PATTERN ]]; then
        log_message "ERROR" "Username tidak valid: $user"
        return 1
    fi
    
    if ! validate_path "$HOMEDIR" "/home"; then
        log_message "ERROR" "Home directory tidak valid untuk user: $user"
        return 1
    fi
    
    if [ ! -f /var/cpanel/users/$user ]; then
        log_message "ERROR" "File user tidak ditemukan: $user"
        return 1
    elif [ "$HOMEDIR" == "" ]; then
        log_message "ERROR" "Tidak dapat menentukan home directory untuk: $user"
        return 1
    fi
    
    # Proses perubahan permission
    log_message "INFO" "Mengatur ownership untuk user $user"
    timeout_command $TIMEOUT_DURATION "chown -R $user:$user $HOMEDIR"
    chmod 711 $HOMEDIR
    chown $user:nobody $HOMEDIR/public_html $HOMEDIR/.htpasswds
    chown $user:mail $HOMEDIR/etc $HOMEDIR/etc/*/shadow $HOMEDIR/etc/*/passwd
    
    # Proses perubahan permission file dan direktori
    log_message "INFO" "Mengatur permission untuk user $user"
    
    echo -n "Mengubah permission file ke 644..."
    timeout_command $TIMEOUT_DURATION "find $HOMEDIR -type f -exec chmod 644 {} \;" & spinner $!
    echo " Selesai."
    
    echo -n "Mengubah permission direktori ke 755..."
    timeout_command $TIMEOUT_DURATION "find $HOMEDIR -type d -exec chmod 755 {} \;" & spinner $!
    echo " Selesai."
    
    echo -n "Mengubah permission cgi-bin ke 755..."
    timeout_command $TIMEOUT_DURATION "find $HOMEDIR -type d -name cgi-bin -exec chmod 755 {} \;" & spinner $!
    echo " Selesai."
    
    echo -n "Mengubah permission script ke 755..."
    timeout_command $TIMEOUT_DURATION "find $HOMEDIR -type f \( -name \"*.pl\" -o -name \"*.perl\" \) -exec chmod 755 {} \;" & spinner $!
    echo " Selesai."
    
    # Proses public_html
    log_message "INFO" "Mengatur permission public_html ke 750"
    chmod 750 $HOMEDIR/public_html & spinner $!
    
    # Proses cagefs jika ada
    if [ -d "$HOMEDIR/.cagefs" ]; then
        log_message "INFO" "Mengatur permission .cagefs"
        chmod 771 $HOMEDIR/.cagefs & spinner $!
        chmod 700 $HOMEDIR/.cagefs/tmp & spinner $!
        chmod 700 $HOMEDIR/.cagefs/var & spinner $!
        chmod 700 $HOMEDIR/.cagefs/opt/ & spinner $!
    fi
    
    log_message "INFO" "Selesai memproses user: $user"
    return 0
}

# Main script
main() {
    # Cek root privileges
    if [ "$EUID" -ne 0 ]; then 
        log_message "ERROR" "Script harus dijalankan sebagai root"
        exit 1
    fi
    
    # Proses argument
    if [ "$#" -lt "1" ]; then
        show_help
        exit 1
    fi
    
    # Cek opsi
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--version)
            echo "Version: 0.2"
            exit 0
            ;;
    esac
    
    # Proses setiap user
    for user in "$@"; do
        process_user "$user"
    done
}

# Trap untuk error handling
trap 'log_message "ERROR" "Error pada baris $LINENO"' ERR

# Jalankan main function
main "$@"
