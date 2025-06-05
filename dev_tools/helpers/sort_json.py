import json
import sys

# Use command-line argument for JSON path
if len(sys.argv) < 2:
    print("Usage: python sort_json.py <path_to_json>")
    sys.exit(1)

json_path = sys.argv[1]

# Define custom category order
CATEGORY_ORDER = ["time", "pvoc", "utility"]

# Define desired parameter field order
FIELD_ORDER = [
    "paramname", "paramdescription", "automatable", "outputduration", "time",
    "min", "max", "flag", "minrange", "maxrange", "step",
    "value", "exponential", "uitype"
]

def category_sort_key(item):
    category = item.get("category", "").lower()
    return CATEGORY_ORDER.index(category) if category in CATEGORY_ORDER else len(CATEGORY_ORDER)

def extract_param_index(param_key):
    # Extract number from param key like 'param1', 'param10'
    try:
        return int(''.join(filter(str.isdigit, param_key)))
    except:
        return float('inf')

def reorder_param_fields(param):
    # Reorder fields within a single parameter dict
    ordered = {field: param[field] for field in FIELD_ORDER if field in param}
    for k in param:
        if k not in ordered:
            ordered[k] = param[k]
    return ordered

# Load JSON
with open(json_path, "r", encoding="utf-8") as f:
    data = json.load(f)

# Convert dict to sortable list
items = [{"key": k, **v} for k, v in data.items()]

# Sort items by category, subcategory, and title
items_sorted = sorted(items, key=lambda item: (
    category_sort_key(item),
    item.get("subcategory", "").lower(),
    item.get("title", "").lower()
))

# Process each item's parameters
for item in items_sorted:
    parameters = item.get("parameters", {})
    # Sort parameter keys like param1, param2, ..., param10
    sorted_keys = sorted(parameters.keys(), key=extract_param_index)
    # Reorder fields inside each parameter
    sorted_parameters = {
        k: reorder_param_fields(parameters[k]) for k in sorted_keys
    }
    item["parameters"] = sorted_parameters

# Rebuild dictionary with sorted keys
sorted_data = {
    item["key"]: {k: item[k] for k in item if k != "key"}
    for item in items_sorted
}

# Overwrite original file
with open(json_path, "w", encoding="utf-8") as f:
    json.dump(sorted_data, f, indent=2, ensure_ascii=False)

print(f"Sorted and overwritten: {json_path}")