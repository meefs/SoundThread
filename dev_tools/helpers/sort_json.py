import json
import sys
from collections import OrderedDict

# --- Custom category order ---
CATEGORY_ORDER = ["time", "pvoc", "utility"]

# --- Desired param key order ---
PARAM_ORDER = [
    "paramname",
    "paramdescription",
    "automatable",
    "time",
    "min",
    "max",
    "flag",
    "minrange",
    "maxrange",
    "step",
    "value",
    "exponential",
    "uitype"
]

# --- Load JSON path from args ---
if len(sys.argv) < 2:
    print("Usage: python sort_json.py path_to_json")
    sys.exit(1)

json_path = sys.argv[1]

with open(json_path, "r", encoding="utf-8") as f:
    data = json.load(f)

# --- Reorder parameter fields ---
def reorder_param_fields(param):
    return OrderedDict((k, param[k]) for k in PARAM_ORDER if k in param)

# --- Convert to sortable items ---
items = [{"key": k, **v} for k, v in data.items()]

# --- Sort by category, subcategory, title ---
items_sorted = sorted(
    items,
    key=lambda item: (
        CATEGORY_ORDER.index(item.get("category", "")) if item.get("category", "") in CATEGORY_ORDER else 999,
        item.get("subcategory", "").lower(),
        item.get("title", "").lower()
    )
)

# --- Rebuild with sorted parameter fields ---
sorted_data = {}
for item in items_sorted:
    key = item.pop("key")
    if "parameters" in item:
        item["parameters"] = {
            param_key: reorder_param_fields(param_val)
            for param_key, param_val in item["parameters"].items()
        }
    sorted_data[key] = item

# --- Overwrite the original file ---
with open(json_path, "w", encoding="utf-8") as f:
    json.dump(sorted_data, f, indent=2, ensure_ascii=False)

print(f"Sorted JSON saved to {json_path}")
