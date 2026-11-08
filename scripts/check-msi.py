# The server swaps the placeholder bytes in place: it must be in the file exactly once, in one piece.
import sys, hashlib
d = open(sys.argv[1], 'rb').read()
pat = b'GLH-CODE-PLACEHOLDER-' + b'X' * 27
print('placeholder found', d.count(pat), 'time(s) in one piece; sha256', hashlib.sha256(d).hexdigest())
sys.exit(0 if d.count(pat) == 1 else 1)
