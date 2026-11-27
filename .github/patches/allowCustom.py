import sys


def remove_line_block(filepath, start_phrase, lines_to_remove_after_start):
    """
    Removes a starting line and a fixed number of lines immediately following it.

    :param filepath: The path to the file to modify.
    :param start_phrase: The unique string to identify the first line of the block.
    :param lines_to_remove_after_start: The number of lines to remove after the starting line.
    :return: True when the block was found and removed.
    """

    total_lines_to_skip = 1 + lines_to_remove_after_start

    try:
        with open(filepath, 'r', encoding='utf-8') as file:
            lines = file.readlines()
    except FileNotFoundError:
        print(f"Error: File not found at {filepath}", file=sys.stderr)
        return False

    start = None
    for i, line in enumerate(lines):
        if line.strip().startswith(start_phrase.strip()):
            start = i
            break

    if start is None:
        # A retry of the workflow step (or a source tree that was already
        # patched) has no signature block left.  If the renamed path is
        # already present this is success, not a broken upstream change.
        if "custom_.txt" in "".join(lines):
            print(f"{filepath} is already patched; nothing to do.")
            return True
        print(
            f"Error: could not find the signature block starting with "
            f"'{start_phrase.strip()}' in {filepath}. RustDesk may have changed "
            f"read_custom_client(); refusing to build a client whose custom "
            f"config would be silently rejected by signature verification.",
            file=sys.stderr,
        )
        return False

    block = "".join(lines[start:start + total_lines_to_skip])
    if "get_rs_pk" not in block or "sign::verify" not in block:
        print(
            f"Error: the block at {filepath}:{start + 1} no longer looks like the "
            f"custom-client signature check (expected get_rs_pk and sign::verify). "
            f"Refusing to remove lines blindly.",
            file=sys.stderr,
        )
        return False

    remaining = lines[:start] + lines[start + total_lines_to_skip:]
    remaining = [line.replace("custom.txt", "custom_.txt") for line in remaining]

    try:
        with open(filepath, 'w', encoding='utf-8') as file:
            file.writelines(remaining)
    except IOError as e:
        print(f"An error occurred while writing to the file: {e}", file=sys.stderr)
        return False

    print(
        f"Success! Removed the {total_lines_to_skip}-line block starting with "
        f"'{start_phrase.strip()}' from {filepath}."
    )
    return True


def main():
    file_path = 'src/common.rs'
    start_phrase = 'const KEY: &str = "5Qbwsde3unUcJBtrx9ZkvUmwFNoExHzpryHuPUdqlWM=";'
    lines_to_remove_after_start = 8
    if not remove_line_block(file_path, start_phrase, lines_to_remove_after_start):
        sys.exit(1)


if __name__ == '__main__':
    main()
