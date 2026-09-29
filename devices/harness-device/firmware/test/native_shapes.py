"""Use the firmware's real protocol capacities and POD structs in host tests."""
from pathlib import Path
import re

MAIN = Path(__file__).resolve().parent / '../main'
PROTOCOL = (MAIN / 'cable_client.h').read_text()


def defines(*names, source=PROTOCOL):
    return ''.join(re.search(r'^#define ' + re.escape(name) + r'\s+[^\n]+$', source, re.M).group(0) + '\n'
                   for name in names)


def typedef(name, source=PROTOCOL):
    for match in re.finditer(r'typedef struct\s*\{[^}]*\}\s*(\w+);', source):
        if match[1] == name:
            return match[0] + '\n'
    raise ValueError(f'No flat production struct named {name}')
