import re

with open('referencias.bib', 'r', encoding='utf-8') as f:
    content = f.read()

# Find the LAST occurrence of @article{rousseeuw1987, ... }
pattern = r'@article\{rousseeuw1987,[\s\S]*?\}'
matches = list(re.finditer(pattern, content))

if len(matches) > 1:
    last_match = matches[-1]
    # Remove the last match
    new_content = content[:last_match.start()] + content[last_match.end():]
    with open('referencias.bib', 'w', encoding='utf-8') as f:
        f.write(new_content)
    print("Duplicate rousseeuw1987 removed.")
else:
    print("No duplicates found or script failed.")
