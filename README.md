# cPanel Fix Permission

[![Version](https://img.shields.io/badge/version-0.2-blue.svg)](https://github.com/nocturnalismee/cpanel-fix-permission)
[![License](https://img.shields.io/badge/license-GPLv3-green.svg)](LICENSE)

A simple bash script to fix permissions and ownership of files/folders in cPanel accounts. This script helps server administrators quickly resolve permission issues in cPanel accounts.

## Features

- ✅ Automatic file and folder permission fixes
- ✅ Support for single and multiple users
- ✅ Security validation to prevent path traversal
- ✅ Timeout for long-running operations
- ✅ Informative logging
- ✅ Progress indicator
- ✅ CageFS support

## Requirements

- Linux/Unix operating system
- cPanel/WHM installation
- Root access
- Bash shell

## Installation

1. Download the script:

```bash
wget https://raw.githubusercontent.com/nocturnalismee/cpanel-fix-permission/main/cpanelfixperm.sh
```

2. Make it executable:

```bash
chmod +x cpanelfixperm.sh
```

## Usage

### Available Options

```bash
./cpanelfixperm.sh [options] username1 [username2 ...]
```

Available options:

- `-h, --help` : Display help information
- `-v, --version` : Display script version

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
for i in `ls -A /var/cpanel/users` ; do ./cpanelfixperm.sh $i ; done
```

## Permission Settings

The script will set the following permissions:

- Home directory: 711 (rwx--x--x)
- Files: 644 (rw-r--r--)
- Directories: 755 (rwxr-xr-x)
- CGI scripts: 755 (rwxr-xr-x)
- public_html: 750 (rwxr-x---)
- CageFS directories: 771/700 (as needed)

## Logging

The script will save logs to:

```
/etc/tmp/cpanel-fix-permission.log
```

Log format:

```
[timestamp] [LEVEL] message
```

## Security

- Username input validation
- Path traversal prevention
- Timeout for long-running operations
- Home directory validation
- Root privileges check

## Troubleshooting

If you encounter issues:

1. Ensure the script is run as root
2. Check the log file for error details
3. Verify the username is valid
4. Check server connectivity

## Contributing

Feel free to submit pull requests. For major changes, please open an issue first to discuss what you would like to change.

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

The GNU General Public License is a free, copyleft license that ensures the software remains free and open source. This license is particularly suitable for system administration tools and security-related software.

Key points of GPL v3.0:

- You are free to use, modify, and distribute the software
- Any modifications must be released under the same license
- You must include the original copyright notice
- You must state significant changes made to the software
- You must make the source code available

## Author

- nocturnalismee

## Support

If you find any bugs or have suggestions, please open an issue in the GitHub repository.
