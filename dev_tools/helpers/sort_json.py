import json

# Load the JSON
with open("process_help.json", "r", encoding="utf-8") as f:
    data = json.load(f)

# Convert dict to list of items with their keys
items = [
    {"key": k, **v}
    for k, v in data.items()
]

# Sort by subcategory first, then by title
items_sorted = sorted(
    items,
    key=lambda item: (
	item.get("category", "").lower(),
        item.get("subcategory", "").lower(),
        item.get("title", "").lower()
    )
)

# Convert back to dict, using the original keys (still sorted)
sorted_data = {item["key"]: {k: item[k] for k in item if k != "key"} for item in items_sorted}

# Write the sorted JSON back out
with open("process_help_sorted.json", "w", encoding="utf-8") as f:
    json.dump(sorted_data, f, indent=2, ensure_ascii=False)

print("Sorted JSON saved to process_help_sorted.json")
