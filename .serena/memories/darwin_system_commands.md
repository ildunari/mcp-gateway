# Darwin (macOS) System Commands

## File System Commands

### Navigation
```bash
# List files with details
ls -la              # All files including hidden
ls -lah             # Human-readable sizes
ls -lat             # Sort by time

# Change directory
cd /path/to/dir     # Absolute path
cd ~/Documents      # Home-relative path
cd -                # Previous directory

# Print working directory
pwd
```

### File Operations
```bash
# Copy files
cp source dest      # Copy file
cp -r source dest   # Copy directory recursively
cp -p source dest   # Preserve attributes

# Move/rename
mv old new          # Rename or move

# Remove
rm file             # Remove file
rm -rf dir          # Remove directory (careful!)
rmdir emptydir      # Remove empty directory

# Create
touch file.txt      # Create empty file
mkdir dirname       # Create directory
mkdir -p a/b/c      # Create nested directories
```

### File Content
```bash
# View files
cat file.txt        # Display entire file
head -n 20 file     # First 20 lines
tail -n 20 file     # Last 20 lines
tail -f logfile     # Follow log file
less file.txt       # Page through file

# Search in files
grep pattern file   # Search for pattern
grep -r pattern .   # Recursive search
grep -i pattern     # Case insensitive
grep -n pattern     # Show line numbers
```

### Finding Files
```bash
# Find command
find . -name "*.js"           # Find by name
find . -type f -size +1M      # Files larger than 1MB
find . -mtime -7              # Modified in last 7 days

# Using mdfind (macOS Spotlight)
mdfind -name filename         # Fast file search
mdfind "kMDItemFSName == *.js"  # Find JavaScript files
```

## Process Management
```bash
# List processes
ps aux              # All processes
ps aux | grep node  # Find node processes
pgrep -f pattern    # Find process by pattern

# Kill processes
kill PID            # Graceful termination
kill -9 PID         # Force kill
killall processname # Kill by name

# Monitor processes
top                 # Interactive process viewer
htop                # Better process viewer (if installed)
```

## Network Commands
```bash
# Check ports
lsof -i :4242       # What's using port 4242
netstat -an | grep 4242  # Port connections

# Test connections
curl http://localhost:4242/health
curl -I URL         # Headers only
ping hostname       # Test connectivity
```

## macOS Specific
```bash
# Open in Finder
open .              # Open current directory
open file.txt       # Open with default app

# Clipboard
pbcopy < file.txt   # Copy file to clipboard
pbpaste > file.txt  # Paste clipboard to file
echo "text" | pbcopy

# System info
sw_vers             # macOS version
system_profiler     # Detailed system info
```

## Permissions
```bash
# View permissions
ls -la              # See permissions
stat file           # Detailed file info

# Change permissions
chmod 755 script.sh # Make executable
chmod +x script.sh  # Add execute permission
chmod -R 644 dir    # Recursive permission change

# Change ownership
chown user:group file
sudo chown -R user dir  # Recursive ownership
```

## Environment
```bash
# View environment
env                 # All environment variables
echo $PATH          # View PATH
printenv VARNAME    # Print specific variable

# Set environment
export VAR=value    # Set for session
echo "export VAR=value" >> ~/.zshrc  # Permanent
```