# cPanel Fix Permission

[![Version](https://img.shields.io/badge/version-0.1-blue.svg)](https://github.com/nocturnalismee/cpanel-fix-permission)
[![License](https://img.shields.io/badge/license-GPLv3-green.svg)](LICENSE)

A powerful and secure bash script to fix permissions and ownership of files/folders in cPanel accounts. This script helps server administrators quickly resolve permission issues in cPanel accounts with enhanced security features.

## ✨ Features

- ✅ Automatic file and folder permission fixes
- ✅ Support for single and multiple users
- ✅ Process all cPanel accounts with single command
- ✅ Security validation to prevent path traversal
- ✅ Timeout for long-running operations
- ✅ Informative logging with color-coded output
- ✅ Progress indicator with spinner
- ✅ CageFS support
- ✅ Input validation and sanitization

## 📋 Requirements

- Linux/Unix operating system
- cPanel/WHM installation
- Root access
- Bash shell
- `realpath` command (usually pre-installed)

## 🚀 Installation

1. Download the script:

```bash
wget https://raw.githubusercontent.com/nocturnalismee/cpanel-fix-permission/main/cpanelfixperm.sh
```

2. Make it executable:

```bash
chmod +x cpanelfixperm.sh
```

## 💻 Usage

### Available Options

```bash
./cpanelfixperm.sh [options] username1 [username2 ...]
```

Available options:

- `-h, --help` : Display help information
- `-v, --version` : Display script version
- `-a, --all` : Fix all cPanel accounts

### Usage Examples

1. Fix a single cPanel account:

```bash
./cpanelfixperm.sh usernameA
```

2. Fix multiple cPanel accounts:

```bash
./cpanelfixperm.sh usernameA usernameB usernameC
```

3. Fix all cPanel accounts in WHM:

```bash
./cpanelfixperm.sh -a
```

## 🔒 Permission Settings

The script will set the following permissions:

| Path/File Type     | Permission | Description |
| ------------------ | ---------- | ----------- |
| Home directory     | 711        | rwx--x--x   |
| Files              | 644        | rw-r--r--   |
| Directories        | 755        | rwxr-xr-x   |
| CGI scripts        | 755        | rwxr-xr-x   |
| public_html        | 750        | rwxr-x---   |
| CageFS directories | 771/700    | As needed   |

## 📝 Logging

The script will save logs to:

```
cpanel-fix-permission.log
```

Log format:

```
[timestamp] [LEVEL] message
```

Log levels:

- INFO: Green color
- WARN: Yellow color
- ERROR: Red color

## 🛡️ Security Features

- Username input validation using regex pattern
- Path traversal prevention using realpath
- Timeout for long-running operations (default: 300 seconds)
- Home directory validation
- Root privileges check
- Secure command execution
- Error handling with trap

## 🔍 Troubleshooting

If you encounter issues:

1. Ensure the script is run as root
2. Check the log file for error details
3. Verify the username is valid
4. Check server connectivity
5. Ensure all required commands are available
6. Check disk space availability

## 🤝 Contributing

Feel free to submit pull requests. For major changes, please open an issue first to discuss what you would like to change.

## 📄 License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

The GNU General Public License is a free, copyleft license that ensures the software remains free and open source. This license is particularly suitable for system administration tools and security-related software.

Key points of GPL v3.0:

- You are free to use, modify, and distribute the software
- Any modifications must be released under the same license
- You must include the original copyright notice
- You must state significant changes made to the software
- You must make the source code available

## 👤 Author

- nocturnalismee

## 💬 Support

If you find any bugs or have suggestions, please open an issue in the GitHub repository.

## ⚠️ Disclaimer

This script is provided "as is", without warranty of any kind. Always backup your data before running any system administration scripts.

### Reference for this script bash

- [PeachFlame/cPanel-fixperms](https://github.com/PeachFlame/cPanel-fixperms)
- [thecpaneladmin](https://www.thecpaneladmin.com/fix-account-permissions/)
