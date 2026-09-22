"""Check catalog coverage for inline Swift L(...) messages, without building the app."""
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = ("en", "ja", "ko", "zh-Hant")


def swift_strings(source):
    """Read ordinary strings and nested interpolations used by our localization API."""
    def string_at(index):
        index += 1
        key, nested, arguments = "", [], 0
        while index < len(source):
            if source[index] == '"':
                return index + 1, key, nested
            if source.startswith('\\(', index):
                key += '{' + str(arguments) + '}'
                arguments += 1
                index += 2
                depth = 1
                while depth:
                    if source[index] == '"':
                        end, child_key, children = string_at(index)
                        nested.extend(children + [(index, child_key)])
                        index = end
                    elif source[index] == '(':
                        depth += 1
                        index += 1
                    elif source[index] == ')':
                        depth -= 1
                        index += 1
                    else:
                        index += 1
            elif source[index] == '\\':
                key += {'n': '\n', 'r': '\r', 't': '\t', '0': '\0'}.get(source[index + 1], source[index + 1])
                index += 2
            else:
                key += source[index]
                index += 1
        raise ValueError('Unterminated Swift string')

    index = 0
    while index < len(source):
        if source.startswith('//', index):
            end = source.find('\n', index)
            index = len(source) if end < 0 else end
        elif source.startswith('/*', index):
            index = source.index('*/', index) + 2
        elif source[index] == '"':
            end, key, nested = string_at(index)
            yield from nested
            yield index, key
            index = end
        else:
            index += 1


def main():
    messages = set()
    for path in (ROOT / 'app/Sources').rglob('*.swift'):
        source = path.read_text()
        for index, key in swift_strings(source):
            if re.search(r'\bL\(\s*$', source[max(0, index - 16):index]):
                messages.add(key)
    placeholder = re.compile(r'\{\d+\}|%(?:[0-9.]+)?[@df]')
    catalog_keys = None
    for language in LANGUAGES:
        path = ROOT / f'app/Sources/VoxInkCore/Resources/{language}.json'
        catalog = json.loads(path.read_text())
        missing = messages - catalog.keys()
        if missing:
            raise ValueError(f'{language}: untranslated messages: {sorted(missing)}')
        if catalog_keys is not None and catalog_keys != catalog.keys():
            raise ValueError(f'{language}: catalog keys differ')
        catalog_keys = catalog.keys()
        for key, value in catalog.items():
            if not value or sorted(placeholder.findall(key)) != sorted(placeholder.findall(value)):
                raise ValueError(f'{language}: empty translation or mismatched placeholders: {key}')
        print(f'{language}: {len(messages)} source messages covered; {len(catalog)} translations validated')


if __name__ == '__main__':
    main()
