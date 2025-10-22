#!/usr/bin/env python3
"""
format_test_output.py
Post-processes Neovim plenary test output to:
1. Dim "Testing:" headers for empty test files (files with no actual test results)
2. Wrap long test descriptions at word boundaries, maintaining indentation
"""

import sys
import re
import shutil

# ANSI color codes
DIM = '\033[2m'
GRAY = '\033[90m'
RESET = '\033[0m'

# Get terminal width
TERM_WIDTH = shutil.get_terminal_size((120, 24)).columns

def is_empty_test_file_section(lines, start_idx):
    """
    Check if a test file section is empty (no actual test output).
    A section is empty if it only has the header and maybe the initialization line.
    """
    # Look ahead for actual test content
    found_content_lines = 0
    for i in range(start_idx, min(start_idx + 15, len(lines))):
        line = lines[i].strip()

        # Skip initialization messages - these don't count as test content
        if 'initialized' in line.lower() or not line:
            continue

        # If we hit the next section divider, stop looking
        if line.startswith('=') and i > start_idx:
            return found_content_lines == 0

        # Signs of actual test content (test results)
        if any(indicator in line for indicator in [
            '✓', '✗', 'Success', 'Failure', 'passed', 'failed',
            'it(', 'describe(', 'PASS', 'FAIL', 'Error', 'pending'
        ]):
            return False

        # Count non-empty, non-init lines as potential content
        if line:
            found_content_lines += 1

    # If we found no meaningful content lines, it's empty
    return found_content_lines == 0

def wrap_text_with_indent(text, indent_len, max_width):
    """
    Wrap text at word boundaries while preserving indentation on continuation lines.
    """
    if len(text) <= max_width:
        return [text]

    lines = []
    words = text.split()

    if not words:
        return [text]

    # First line might already have some content with indent
    match = re.match(r'^(\s*)(.*)', text)
    if match:
        initial_indent = match.group(1)
        remaining = match.group(2)
        words = remaining.split()
    else:
        initial_indent = ''

    # Build lines
    current_line = initial_indent
    indent_str = ' ' * indent_len

    for i, word in enumerate(words):
        # For first word, don't add space
        if i == 0:
            test_line = current_line + word
        else:
            test_line = current_line + ' ' + word

        if len(test_line) <= max_width:
            current_line = test_line
        else:
            # Current line is full, start new line
            if current_line.strip():  # Only add if not empty
                lines.append(current_line)
            current_line = indent_str + word

    # Add the last line
    if current_line.strip():
        lines.append(current_line)

    return lines if lines else [text]

def process_test_output():
    """Process stdin and write formatted output to stdout."""
    lines = []
    for line in sys.stdin:
        lines.append(line.rstrip('\n'))

    i = 0
    while i < len(lines):
        line = lines[i]

        # Detect "Testing:" headers
        if line.strip().startswith('=' * 10):  # Divider line
            # Check if next line is a "Testing:" header
            if i + 1 < len(lines) and lines[i + 1].strip().startswith('Testing:'):
                # Check if this test file section is empty
                is_empty = is_empty_test_file_section(lines, i + 2)

                if is_empty:
                    # Print divider and header in dim/gray
                    print(f"{GRAY}{line}{RESET}")
                    print(f"{GRAY}{lines[i + 1]}{RESET}")
                    i += 2
                    continue

        # Handle potentially long test descriptions with status symbols
        match = re.match(r'^(\s*)(✓|✗|[0-9]+\)|•|\*)\s+(.*)$', line)
        if match:
            indent = match.group(1)
            status = match.group(2)
            description = match.group(3)

            # Calculate the indentation for wrapped lines
            # It should align with where the description text starts
            indent_len = len(indent) + len(status) + 1  # +1 for space after status

            # Reconstruct the line
            full_line = f"{indent}{status} {description}"

            # Check if wrapping is needed
            if len(full_line) > TERM_WIDTH:
                # Wrap the description part
                wrapped_lines = wrap_text_with_indent(description, indent_len, TERM_WIDTH - indent_len)

                # Print first line with status symbol
                print(f"{indent}{status} {wrapped_lines[0]}")

                # Print continuation lines with proper indentation
                indent_str = ' ' * indent_len
                for wrapped_line in wrapped_lines[1:]:
                    # wrapped_line already has indentation from wrap_text_with_indent
                    print(wrapped_line)

                i += 1
                continue

        # Print line as-is if no special handling needed
        print(line)
        i += 1

if __name__ == '__main__':
    try:
        process_test_output()
    except KeyboardInterrupt:
        sys.exit(0)
    except BrokenPipeError:
        # Handle pipe being closed
        sys.exit(0)
